// Native AKE socket hub (plan 28, Linux added in plan 44.6): BSD
// sockets with IP TTL 3 and TCP_NODELAY (the DTCP-IP proximity
// requirement the reference client implements), exposed to Dart over
// the ake_socket channels. This mirrors the iOS/macOS Swift
// implementation (AkeSocket.swift) method for method:
//
//   MethodChannel com.markun.tmhb/ake_socket
//     connect {id, host, port} -> null, or PlatformException
//             (code "connect_failed" / "bad_args")
//     send    {id, data}        -> null (errors are swallowed)
//     close   {id}              -> null
//   EventChannel com.markun.tmhb/ake_socket_events
//     {id, kind: "data",  data: <bytes>}
//     {id, kind: "error", message: <string>}
//     {id, kind: "done"}
//
// The nasne refuses the AKE TCP connection itself (RST) when the TTL
// is above 3 (plan 44.5), and dart:io has no TTL API, which is why
// this native path exists on every desktop/mobile platform.

#include "ake_socket.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr int kAkeIpTtl = 3;
constexpr int kConnectTimeoutMs = 10000;
constexpr size_t kReadBufferSize = 16384;

// The hub owns the channels and the live connections. It is created
// once at registration and lives for the rest of the process (like
// the Swift hub's shared singleton), so raw pointers to it stay
// valid.
struct AkeHub {
  FlMethodChannel* method_channel = nullptr;
  FlEventChannel* event_channel = nullptr;
  std::map<int64_t, std::shared_ptr<struct AkeConnection>> connections;
  std::mutex mutex;
  bool listening = false;

  // Emits one event (takes ownership of |event|). Callable from any
  // thread: the actual FlEventChannel call is posted to the main
  // loop, like the Swift hub dispatching to the main queue.
  void Emit(FlValue* event);
};

struct EmitData {
  AkeHub* hub;
  FlValue* event;  // owned
};

gboolean EmitOnMain(gpointer user_data) {
  auto* data = static_cast<EmitData*>(user_data);
  if (data->hub->listening && data->hub->event_channel != nullptr) {
    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(data->hub->event_channel, data->event,
                               nullptr, &error)) {
      g_warning("ake_socket: failed to send event: %s", error->message);
    }
  }
  fl_value_unref(data->event);
  delete data;
  return G_SOURCE_REMOVE;
}

void AkeHub::Emit(FlValue* event) {
  g_idle_add(EmitOnMain, new EmitData{this, event});
}

FlValue* MakeEvent(int64_t id, const char* kind) {
  FlValue* event = fl_value_new_map();
  fl_value_set_string_take(event, "id", fl_value_new_int(id));
  fl_value_set_string_take(event, "kind", fl_value_new_string(kind));
  return event;
}

// One native AKE connection: setsockopt(IP_TTL, 3) and TCP_NODELAY
// before connect, a poll-bounded nonblocking connect, then a
// blocking recv loop on a background thread.
struct AkeConnection : std::enable_shared_from_this<AkeConnection> {
  const int64_t id;
  AkeHub* hub;  // not owned; the hub outlives every connection
  int fd = -1;
  std::atomic<bool> running{false};
  std::atomic<bool> closed{false};
  std::mutex send_mutex;

  AkeConnection(int64_t connection_id, AkeHub* owner)
      : id(connection_id), hub(owner) {}

  ~AkeConnection() { Close(); }

  // Blocking connect (run on a worker thread). On failure returns
  // false and fills |error| with the same message shape the Swift
  // implementation produces.
  bool Connect(const std::string& host, int port, std::string* error) {
    // Resolve (the host is normally an IPv4 literal handed over by
    // the source's HEAD response).
    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* resolved = nullptr;
    const std::string service = std::to_string(port);
    if (getaddrinfo(host.c_str(), service.c_str(), &hints, &resolved) != 0 ||
        resolved == nullptr) {
      *error = "could not resolve " + host;
      return false;
    }

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
      *error = std::string("socket() failed: ") + strerror(errno);
      freeaddrinfo(resolved);
      return false;
    }
    int ttl = kAkeIpTtl;
    setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl, sizeof(ttl));
    int no_delay = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &no_delay, sizeof(no_delay));

    const int flags = fcntl(fd, F_GETFL);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    sockaddr address = *resolved->ai_addr;
    const socklen_t address_length = resolved->ai_addrlen;
    freeaddrinfo(resolved);
    const int connect_result = connect(fd, &address, address_length);
    if (connect_result != 0) {
      if (errno != EINPROGRESS) {
        *error = std::string("connect failed: ") + strerror(errno);
        ::close(fd);
        fd = -1;
        return false;
      }
      pollfd poll_fd{fd, POLLOUT, 0};
      const int ready = poll(&poll_fd, 1, kConnectTimeoutMs);
      if (ready <= 0) {
        ::close(fd);
        fd = -1;
        *error = "connect timed out";
        return false;
      }
      int socket_error = 0;
      socklen_t length = sizeof(socket_error);
      getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error, &length);
      if (socket_error != 0) {
        *error = std::string("connect failed: ") + strerror(socket_error);
        ::close(fd);
        fd = -1;
        return false;
      }
    }
    fcntl(fd, F_SETFL, flags);
    if (closed.load()) {
      // Dart closed the connection while the connect was in flight.
      ::close(fd);
      fd = -1;
      return false;
    }
    running.store(true);
    auto self = shared_from_this();
    std::thread([self]() { self->ReadLoop(); }).detach();
    return true;
  }

  void ReadLoop() {
    std::vector<uint8_t> buffer(kReadBufferSize);
    while (running.load()) {
      const ssize_t count = recv(fd, buffer.data(), buffer.size(), 0);
      if (count > 0) {
        FlValue* event = MakeEvent(id, "data");
        fl_value_set_string_take(
            event, "data",
            fl_value_new_uint8_list(buffer.data(),
                                    static_cast<size_t>(count)));
        hub->Emit(event);
      } else if (count == 0) {
        if (running.load()) hub->Emit(MakeEvent(id, "done"));
        return;
      } else {
        if (errno == EINTR) continue;
        if (running.load()) {
          FlValue* event = MakeEvent(id, "error");
          const std::string message =
              std::string("recv failed: ") + strerror(errno);
          fl_value_set_string_take(event, "message",
                                   fl_value_new_string(message.c_str()));
          hub->Emit(event);
        }
        return;
      }
    }
  }

  void Send(const uint8_t* data, size_t length) {
    std::lock_guard<std::mutex> lock(send_mutex);
    if (fd < 0) return;
    size_t offset = 0;
    while (offset < length) {
      const ssize_t sent =
          send(fd, data + offset, length - offset, MSG_NOSIGNAL);
      if (sent <= 0) return;
      offset += static_cast<size_t>(sent);
    }
  }

  void Close() {
    closed.store(true);
    running.store(false);
    if (fd >= 0) {
      shutdown(fd, SHUT_RDWR);
      ::close(fd);
      fd = -1;
    }
  }
};

AkeHub* g_hub = nullptr;

void RespondError(FlMethodCall* method_call, const char* code,
                  const std::string& message) {
  g_autoptr(FlMethodErrorResponse) response =
      fl_method_error_response_new(code, message.c_str(), nullptr);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response),
                              &error)) {
    g_warning("ake_socket: failed to respond: %s", error->message);
  }
}

void RespondSuccess(FlMethodCall* method_call) {
  g_autoptr(FlMethodSuccessResponse) response =
      fl_method_success_response_new(fl_value_new_null());
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response),
                              &error)) {
    g_warning("ake_socket: failed to respond: %s", error->message);
  }
}

// Data carried from the connect worker thread back to the main loop.
struct ConnectResult {
  FlMethodCall* method_call;  // owned reference
  std::shared_ptr<AkeConnection> connection;
  bool ok;
  std::string error;
};

gboolean ConnectDoneOnMain(gpointer user_data) {
  auto* result = static_cast<ConnectResult*>(user_data);
  if (result->ok) {
    RespondSuccess(result->method_call);
  } else {
    {
      std::lock_guard<std::mutex> lock(g_hub->mutex);
      g_hub->connections.erase(result->connection->id);
    }
    RespondError(result->method_call, "connect_failed", result->error);
  }
  g_object_unref(result->method_call);
  delete result;
  return G_SOURCE_REMOVE;
}

void MethodCallHandler(FlMethodChannel* channel, FlMethodCall* method_call,
                       gpointer user_data) {
  AkeHub* hub = g_hub;
  const char* name = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  FlValue* id_value =
      (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
          ? fl_value_lookup_string(args, "id")
          : nullptr;
  if (id_value == nullptr ||
      fl_value_get_type(id_value) != FL_VALUE_TYPE_INT) {
    RespondError(method_call, "bad_args", "missing connection id");
    return;
  }
  const int64_t id = fl_value_get_int(id_value);

  if (strcmp(name, "connect") == 0) {
    FlValue* host_value = fl_value_lookup_string(args, "host");
    FlValue* port_value = fl_value_lookup_string(args, "port");
    if (host_value == nullptr ||
        fl_value_get_type(host_value) != FL_VALUE_TYPE_STRING ||
        port_value == nullptr ||
        fl_value_get_type(port_value) != FL_VALUE_TYPE_INT) {
      RespondError(method_call, "bad_args", "missing host/port");
      return;
    }
    const std::string host = fl_value_get_string(host_value);
    const int port = static_cast<int>(fl_value_get_int(port_value));
    auto connection = std::make_shared<AkeConnection>(id, hub);
    {
      std::lock_guard<std::mutex> lock(hub->mutex);
      hub->connections[id] = connection;
    }
    // The connect can block for seconds; run it off the main thread
    // and respond when it settles (the Swift hub does the same on a
    // global queue). Hold a reference to the method call meanwhile.
    g_object_ref(method_call);
    std::thread([connection, host, port, method_call]() {
      auto* result = new ConnectResult;
      result->method_call = method_call;
      result->connection = connection;
      result->ok = connection->Connect(host, port, &result->error);
      g_idle_add(ConnectDoneOnMain, result);
    }).detach();
    return;
  }

  if (strcmp(name, "send") == 0) {
    FlValue* data_value = fl_value_lookup_string(args, "data");
    if (data_value == nullptr ||
        fl_value_get_type(data_value) != FL_VALUE_TYPE_UINT8_LIST) {
      RespondError(method_call, "bad_args", "missing data");
      return;
    }
    std::shared_ptr<AkeConnection> connection;
    {
      std::lock_guard<std::mutex> lock(hub->mutex);
      auto it = hub->connections.find(id);
      if (it != hub->connections.end()) connection = it->second;
    }
    if (connection != nullptr) {
      connection->Send(fl_value_get_uint8_list(data_value),
                       fl_value_get_length(data_value));
    }
    RespondSuccess(method_call);
    return;
  }

  if (strcmp(name, "close") == 0) {
    std::shared_ptr<AkeConnection> connection;
    {
      std::lock_guard<std::mutex> lock(hub->mutex);
      auto it = hub->connections.find(id);
      if (it != hub->connections.end()) {
        connection = it->second;
        hub->connections.erase(it);
      }
    }
    if (connection != nullptr) connection->Close();
    RespondSuccess(method_call);
    return;
  }

  g_autoptr(FlMethodNotImplementedResponse) response =
      fl_method_not_implemented_response_new();
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response),
                              &error)) {
    g_warning("ake_socket: failed to respond: %s", error->message);
  }
}

FlMethodErrorResponse* ListenHandler(FlEventChannel* channel, FlValue* args,
                                     gpointer user_data) {
  g_hub->listening = true;
  return nullptr;
}

FlMethodErrorResponse* CancelHandler(FlEventChannel* channel, FlValue* args,
                                     gpointer user_data) {
  g_hub->listening = false;
  return nullptr;
}

}  // namespace

void ake_socket_register(FlPluginRegistry* registry) {
  if (g_hub != nullptr) return;
  g_hub = new AkeHub();

  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "AkeSocket");
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  g_autoptr(FlStandardMethodCodec) method_codec =
      fl_standard_method_codec_new();
  g_hub->method_channel = fl_method_channel_new(
      messenger, "com.markun.tmhb/ake_socket", FL_METHOD_CODEC(method_codec));
  fl_method_channel_set_method_call_handler(g_hub->method_channel,
                                            MethodCallHandler, nullptr,
                                            nullptr);

  g_autoptr(FlStandardMethodCodec) event_codec = fl_standard_method_codec_new();
  g_hub->event_channel = fl_event_channel_new(
      messenger, "com.markun.tmhb/ake_socket_events",
      FL_METHOD_CODEC(event_codec));
  fl_event_channel_set_stream_handlers(g_hub->event_channel, ListenHandler,
                                       CancelHandler, nullptr, nullptr);
}
