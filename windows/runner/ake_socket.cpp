// Native AKE socket hub (plan 28, Windows added with the Windows
// desktop port): Winsock2 sockets with IP TTL 3 and TCP_NODELAY
// (the DTCP-IP proximity requirement the reference client
// implements), exposed to Dart over the ake_socket channels. This
// mirrors the Linux implementation (linux/runner/ake_socket.cc)
// method for method:
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
// is above 3 (plan 47.5), and dart:io has no TTL API, which is why
// this native path exists on every desktop/mobile platform.
//
// Threading model (the one platform-specific design choice):
// Flutter's Windows method/event channels — MethodResult and
// EventSink in particular — may only be used on the platform thread,
// which in the Windows runner is the UI thread running the Win32
// message loop. The blocking connect and the blocking recv loop
// therefore run on worker threads (std::thread), and everything a
// worker thread needs to hand back — an event for Dart, or the
// completion of a pending connect call — is packaged into a heap
// PostedWork and sent to the UI thread with
// PostMessage(kAkeSocketMessage). FlutterWindow::MessageHandler
// forwards that message to AkeSocketHandleMessage, which performs
// the actual sink/result call on the UI thread. This is the exact
// analogue of the Linux hub, which posts FlEventChannel calls to
// the GLib main loop with g_idle_add, and of the Swift hub, which
// dispatches sink calls to DispatchQueue.main. EncodableValue event
// payloads are plain value types, so building them on the worker
// thread is safe; only the sink call itself is thread-bound.
// Because every map/sink/result access then happens on the UI
// thread, the hub needs no locking around them; each connection
// still guards its own socket handle for send/close/recv races.

// winsock2.h must be included before windows.h (pulled in by the
// Flutter headers via ake_socket.h) so the old Winsock 1 API in
// windows.h stays disabled.
#include <winsock2.h>
#include <ws2tcpip.h>

#include "ake_socket.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

constexpr int kAkeIpTtl = 3;
constexpr int kConnectTimeoutMs = 10000;
constexpr size_t kReadBufferSize = 16384;

using EncodableValue = flutter::EncodableValue;
using EncodableMap = flutter::EncodableMap;

std::string WsaErrorMessage(const char* what, int error) {
  return std::string(what) + ": WSA error " + std::to_string(error);
}

// Dart ints arrive as int32_t when they fit and int64_t otherwise;
// accept both (the Linux hub's FlValue int is always 64-bit, the
// Windows standard codec is not).
bool GetInt(const EncodableValue& value, int64_t* out) {
  if (const auto* v = std::get_if<int32_t>(&value)) {
    *out = *v;
    return true;
  }
  if (const auto* v = std::get_if<int64_t>(&value)) {
    *out = *v;
    return true;
  }
  return false;
}

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

EncodableValue MakeEvent(int64_t id, const char* kind) {
  EncodableMap event;
  event[EncodableValue("id")] = EncodableValue(id);
  event[EncodableValue("kind")] = EncodableValue(kind);
  return EncodableValue(event);
}

struct AkeConnection;

// Work handed from a worker thread to the UI thread via
// PostMessage(kAkeSocketMessage); ownership passes through the
// message's LPARAM and is reclaimed in AkeSocketHandleMessage.
struct PostedWork {
  enum class Kind { kEvent, kConnectResult };
  Kind kind;
  // kEvent: the fully built event value for the event sink.
  EncodableValue event;
  // kConnectResult: the pending method result plus the outcome.
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
  std::shared_ptr<AkeConnection> connection;
  bool connect_ok = false;
  std::string connect_error;
};

// The hub owns the channels and the live connections. It is created
// once at registration and lives for the rest of the process (like
// the Swift hub's shared singleton), so raw pointers to it stay
// valid. |sink| and |connections| are only touched on the UI thread
// (stream-handler callbacks, method calls and posted work all run
// there), so they need no mutex.
struct AkeHub {
  HWND window_handle = nullptr;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> method_channel;
  std::unique_ptr<flutter::EventChannel<EncodableValue>> event_channel;
  std::unique_ptr<flutter::EventSink<EncodableValue>> sink;
  std::map<int64_t, std::shared_ptr<AkeConnection>> connections;

  // Queues |work| for the UI thread. Called from worker threads.
  void Post(std::unique_ptr<PostedWork> work) {
    PostedWork* raw = work.release();
    if (window_handle == nullptr ||
        !::PostMessage(window_handle, kAkeSocketMessage, 0,
                       reinterpret_cast<LPARAM>(raw))) {
      delete raw;
    }
  }

  // Emits one event to Dart. Called from worker threads; the sink
  // itself is invoked later, on the UI thread.
  void Emit(EncodableValue event) {
    auto work = std::make_unique<PostedWork>();
    work->kind = PostedWork::Kind::kEvent;
    work->event = std::move(event);
    Post(std::move(work));
  }
};

// Stream handler for the event channel: just stashes the sink in
// the hub. Kept as its own object so the event channel owns the
// handler while the hub owns the channel (no self-ownership).
struct AkeStreamHandler : public flutter::StreamHandler<EncodableValue> {
  AkeHub* hub;  // not owned
  explicit AkeStreamHandler(AkeHub* owner) : hub(owner) {}

  // Both callbacks run on the UI thread.
  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
  OnListenInternal(const EncodableValue* arguments,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&&
                       events) override {
    (void)arguments;
    hub->sink = std::move(events);
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<EncodableValue>>
  OnCancelInternal(const EncodableValue* arguments) override {
    (void)arguments;
    hub->sink.reset();
    return nullptr;
  }
};

AkeHub* g_hub = nullptr;

// One native AKE connection: setsockopt(IP_TTL, 3) and TCP_NODELAY
// before connect, a select-bounded nonblocking connect, then a
// blocking recv loop on a background thread.
struct AkeConnection : std::enable_shared_from_this<AkeConnection> {
  const int64_t id;
  AkeHub* hub;  // not owned; the hub outlives every connection
  std::atomic<SOCKET> socket_handle{INVALID_SOCKET};
  std::atomic<bool> running{false};
  std::atomic<bool> closed{false};
  std::mutex send_mutex;

  AkeConnection(int64_t connection_id, AkeHub* owner)
      : id(connection_id), hub(owner) {}

  ~AkeConnection() { Close(); }

  // Blocking connect (run on a worker thread). On failure returns
  // false and fills |error| with the same message shape the Linux
  // and Swift implementations produce.
  bool Connect(const std::string& host, int port, std::string* error) {
    // Winsock is initialised once for the whole hub at
    // registration, so sockets can be created directly here.
    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    addrinfo* resolved = nullptr;
    const std::string service = std::to_string(port);
    if (getaddrinfo(host.c_str(), service.c_str(), &hints, &resolved) != 0 ||
        resolved == nullptr) {
      *error = "could not resolve " + host;
      return false;
    }

    SOCKET handle = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (handle == INVALID_SOCKET) {
      *error = WsaErrorMessage("socket() failed", ::WSAGetLastError());
      freeaddrinfo(resolved);
      return false;
    }
    int ttl = kAkeIpTtl;
    ::setsockopt(handle, IPPROTO_IP, IP_TTL,
                 reinterpret_cast<const char*>(&ttl), sizeof(ttl));
    BOOL no_delay = TRUE;
    ::setsockopt(handle, IPPROTO_TCP, TCP_NODELAY,
                 reinterpret_cast<const char*>(&no_delay), sizeof(no_delay));

    sockaddr address = *resolved->ai_addr;
    const int address_length = static_cast<int>(resolved->ai_addrlen);
    freeaddrinfo(resolved);

    // Nonblocking connect bounded by select(), the Winsock
    // counterpart of the Linux hub's poll() loop.
    u_long nonblocking = 1;
    ::ioctlsocket(handle, FIONBIO, &nonblocking);
    const int connect_result =
        ::connect(handle, &address, address_length);
    if (connect_result == SOCKET_ERROR) {
      const int connect_error = ::WSAGetLastError();
      if (connect_error != WSAEWOULDBLOCK) {
        *error = WsaErrorMessage("connect failed", connect_error);
        ::closesocket(handle);
        return false;
      }
      fd_set write_set;
      FD_ZERO(&write_set);
      FD_SET(handle, &write_set);
      timeval timeout{};
      timeout.tv_sec = kConnectTimeoutMs / 1000;
      timeout.tv_usec = (kConnectTimeoutMs % 1000) * 1000;
      const int ready =
          ::select(0, nullptr, &write_set, nullptr, &timeout);
      if (ready <= 0) {
        ::closesocket(handle);
        *error = "connect timed out";
        return false;
      }
      int socket_error = 0;
      int length = sizeof(socket_error);
      ::getsockopt(handle, SOL_SOCKET, SO_ERROR,
                   reinterpret_cast<char*>(&socket_error), &length);
      if (socket_error != 0) {
        *error = WsaErrorMessage("connect failed", socket_error);
        ::closesocket(handle);
        return false;
      }
    }
    u_long blocking = 0;
    ::ioctlsocket(handle, FIONBIO, &blocking);
    if (closed.load()) {
      // Dart closed the connection while the connect was in flight.
      ::closesocket(handle);
      return false;
    }
    socket_handle.store(handle);
    running.store(true);
    auto self = shared_from_this();
    std::thread([self]() { self->ReadLoop(); }).detach();
    return true;
  }

  void ReadLoop() {
    const SOCKET handle = socket_handle.load();
    std::vector<uint8_t> buffer(kReadBufferSize);
    while (running.load()) {
      const int count =
          ::recv(handle, reinterpret_cast<char*>(buffer.data()),
                 static_cast<int>(buffer.size()), 0);
      if (count > 0) {
        EncodableValue event = MakeEvent(id, "data");
        auto* map = std::get_if<EncodableMap>(&event);
        (*map)[EncodableValue("data")] = EncodableValue(std::vector<uint8_t>(
            buffer.begin(), buffer.begin() + count));
        hub->Emit(std::move(event));
      } else if (count == 0) {
        if (running.load()) hub->Emit(MakeEvent(id, "done"));
        return;
      } else {
        if (running.load()) {
          EncodableValue event = MakeEvent(id, "error");
          auto* map = std::get_if<EncodableMap>(&event);
          (*map)[EncodableValue("message")] =
              EncodableValue(WsaErrorMessage("recv failed",
                                             ::WSAGetLastError()));
          hub->Emit(std::move(event));
        }
        return;
      }
    }
  }

  void Send(const uint8_t* data, size_t length) {
    std::lock_guard<std::mutex> lock(send_mutex);
    const SOCKET handle = socket_handle.load();
    if (handle == INVALID_SOCKET) return;
    size_t offset = 0;
    while (offset < length) {
      const int sent =
          ::send(handle, reinterpret_cast<const char*>(data + offset),
                 static_cast<int>(length - offset), 0);
      if (sent <= 0) return;
      offset += static_cast<size_t>(sent);
    }
  }

  void Close() {
    closed.store(true);
    running.store(false);
    const SOCKET handle = socket_handle.exchange(INVALID_SOCKET);
    if (handle != INVALID_SOCKET) {
      ::shutdown(handle, SD_BOTH);
      ::closesocket(handle);
    }
  }
};

void MethodCallHandler(const flutter::MethodCall<EncodableValue>& call,
                       std::unique_ptr<flutter::MethodResult<EncodableValue>>
                           result) {
  AkeHub* hub = g_hub;
  const EncodableMap* args =
      std::get_if<EncodableMap>(call.arguments());
  const EncodableValue* id_value =
      args == nullptr ? nullptr : Lookup(*args, "id");
  int64_t id = 0;
  if (id_value == nullptr || !GetInt(*id_value, &id)) {
    result->Error("bad_args", "missing connection id");
    return;
  }

  if (call.method_name() == "connect") {
    const EncodableValue* host_value = Lookup(*args, "host");
    const EncodableValue* port_value = Lookup(*args, "port");
    int64_t port = 0;
    if (host_value == nullptr ||
        std::get_if<std::string>(host_value) == nullptr ||
        port_value == nullptr || !GetInt(*port_value, &port)) {
      result->Error("bad_args", "missing host/port");
      return;
    }
    const std::string host = std::get<std::string>(*host_value);
    auto connection = std::make_shared<AkeConnection>(id, hub);
    hub->connections[id] = connection;
    // The connect can block for seconds; run it off the UI thread
    // and reply when it settles (the Linux/Swift hubs do the same).
    // The MethodResult travels with the posted work and is only
    // completed back on the UI thread.
    std::thread([connection, host, port,
                 method_result = std::move(result)]() mutable {
      auto work = std::make_unique<PostedWork>();
      work->kind = PostedWork::Kind::kConnectResult;
      work->result = std::move(method_result);
      work->connection = connection;
      work->connect_ok = connection->Connect(
          host, static_cast<int>(port), &work->connect_error);
      connection->hub->Post(std::move(work));
    }).detach();
    return;
  }

  if (call.method_name() == "send") {
    const EncodableValue* data_value = Lookup(*args, "data");
    const auto* data =
        data_value == nullptr
            ? nullptr
            : std::get_if<std::vector<uint8_t>>(data_value);
    if (data == nullptr) {
      result->Error("bad_args", "missing data");
      return;
    }
    auto it = hub->connections.find(id);
    if (it != hub->connections.end()) {
      it->second->Send(data->data(), data->size());
    }
    result->Success();
    return;
  }

  if (call.method_name() == "close") {
    auto it = hub->connections.find(id);
    if (it != hub->connections.end()) {
      std::shared_ptr<AkeConnection> connection = it->second;
      hub->connections.erase(it);
      connection->Close();
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace

void AkeSocketRegister(flutter::PluginRegistrar* registrar,
                       HWND window_handle) {
  if (g_hub != nullptr) return;

  // Winsock must be started once per process before any socket is
  // created. Version 2.2 is what ws2_32.dll always provides; the
  // matching WSACleanup is deliberately skipped, mirroring the
  // hub's process-lifetime design (the hub never unregisters).
  static std::once_flag wsa_once;
  std::call_once(wsa_once, []() {
    WSADATA wsa_data;
    ::WSAStartup(MAKEWORD(2, 2), &wsa_data);
  });

  // The hub is deliberately leaked to a process-lifetime singleton
  // (same trade-off as the Linux hub's leaked AkeHub and the Swift
  // hub's shared singleton) so the raw g_hub pointer and the
  // channels stay valid for the rest of the process.
  AkeHub* hub = new AkeHub();
  hub->window_handle = window_handle;
  g_hub = hub;

  hub->method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "com.markun.tmhb/ake_socket",
          &flutter::StandardMethodCodec::GetInstance());
  hub->method_channel->SetMethodCallHandler(MethodCallHandler);

  hub->event_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "com.markun.tmhb/ake_socket_events",
          &flutter::StandardMethodCodec::GetInstance());
  hub->event_channel->SetStreamHandler(
      std::make_unique<AkeStreamHandler>(hub));
}

bool AkeSocketHandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  (void)wparam;  // the payload travels in lparam only
  if (message != kAkeSocketMessage || g_hub == nullptr) return false;
  std::unique_ptr<PostedWork> work(
      reinterpret_cast<PostedWork*>(lparam));
  if (work == nullptr) return true;

  switch (work->kind) {
    case PostedWork::Kind::kEvent:
      if (g_hub->sink != nullptr) {
        g_hub->sink->Success(work->event);
      }
      break;
    case PostedWork::Kind::kConnectResult:
      if (work->connect_ok) {
        work->result->Success();
      } else {
        g_hub->connections.erase(work->connection->id);
        work->result->Error("connect_failed", work->connect_error);
      }
      break;
  }
  return true;
}
