import Darwin
import Flutter
import Foundation

/// Native AKE socket hub (plan 28): BSD sockets with IP TTL 3 and
/// TCP_NODELAY (the DTCP-IP proximity requirement the reference
/// client implements), exposed to Dart over the ake_socket
/// channels.
final class AkeSocketHub: NSObject, FlutterStreamHandler {
  static let shared = AkeSocketHub()

  private var sink: FlutterEventSink?
  private var connections: [Int: AkeSocketConnection] = [:]
  private let lock = NSLock()

  func register(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(
      name: "com.markun.tmhb/ake_socket", binaryMessenger: messenger)
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    let events = FlutterEventChannel(
      name: "com.markun.tmhb/ake_socket_events", binaryMessenger: messenger)
    events.setStreamHandler(self)
  }

  // MARK: FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?(event)
    }
  }

  // MARK: Method handling

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let id = args["id"] as? Int else {
      result(FlutterError(code: "bad_args", message: "missing connection id", details: nil))
      return
    }
    switch call.method {
    case "connect":
      guard let host = args["host"] as? String, let port = args["port"] as? Int else {
        result(FlutterError(code: "bad_args", message: "missing host/port", details: nil))
        return
      }
      let connection = AkeSocketConnection(id: id) { [weak self] event in
        self?.emit(event)
      }
      lock.lock()
      connections[id] = connection
      lock.unlock()
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        do {
          try connection.connect(host: host, port: port, timeoutMs: 10000)
          DispatchQueue.main.async { result(nil) }
        } catch {
          self.lock.lock()
          self.connections.removeValue(forKey: id)
          self.lock.unlock()
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "connect_failed", message: "\(error)", details: nil))
          }
        }
      }
    case "send":
      guard let data = args["data"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "missing data", details: nil))
        return
      }
      lock.lock()
      let connection = connections[id]
      lock.unlock()
      connection?.send(data.data)
      result(nil)
    case "close":
      lock.lock()
      let connection = connections.removeValue(forKey: id)
      lock.unlock()
      connection?.close()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// One native AKE connection: setsockopt(IP_TTL, 3) and
/// TCP_NODELAY before connect, a poll-bounded nonblocking connect,
/// then a blocking recv loop on a background queue.
final class AkeSocketConnection {
  let id: Int
  private let emit: ([String: Any]) -> Void
  private var fd: Int32 = -1
  private var running = false
  private let sendLock = NSLock()

  init(id: Int, emit: @escaping ([String: Any]) -> Void) {
    self.id = id
    self.emit = emit
  }

  func connect(host: String, port: Int, timeoutMs: Int) throws {
    // Resolve (the host is normally an IPv4 literal handed over by
    // the source's HEAD response).
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_STREAM
    var resolved: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, "\(port)", &hints, &resolved) == 0, let first = resolved
    else {
      throw NSError(
        domain: "AkeSocket", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "could not resolve \(host)"])
    }
    defer { freeaddrinfo(resolved) }

    fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw NSError(
        domain: "AkeSocket", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "socket() failed: \(String(cString: strerror(errno)))"
        ])
    }
    var ttl: Int32 = 3
    setsockopt(fd, IPPROTO_IP, IP_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
    var noDelay: Int32 = 1
    setsockopt(
      fd, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))

    let flags = fcntl(fd, F_GETFL)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    var address = first.pointee.ai_addr.pointee
    let connectResult = Darwin.connect(fd, &address, first.pointee.ai_addrlen)
    if connectResult != 0 {
      guard errno == EINPROGRESS else {
        let message = String(cString: strerror(errno))
        Darwin.close(fd)
        fd = -1
        throw NSError(
          domain: "AkeSocket", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "connect failed: \(message)"])
      }
      var pollFd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
      let ready = poll(&pollFd, 1, Int32(timeoutMs))
      guard ready > 0 else {
        Darwin.close(fd)
        fd = -1
        throw NSError(
          domain: "AkeSocket", code: 4,
          userInfo: [NSLocalizedDescriptionKey: "connect timed out"])
      }
      var socketError: Int32 = 0
      var length = socklen_t(MemoryLayout<Int32>.size)
      getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
      guard socketError == 0 else {
        let message = String(cString: strerror(socketError))
        Darwin.close(fd)
        fd = -1
        throw NSError(
          domain: "AkeSocket", code: 5,
          userInfo: [NSLocalizedDescriptionKey: "connect failed: \(message)"])
      }
    }
    _ = fcntl(fd, F_SETFL, flags)
    running = true
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.readLoop()
    }
  }

  private func readLoop() {
    var buffer = [UInt8](repeating: 0, count: 16384)
    while running {
      let count = recv(fd, &buffer, buffer.count, 0)
      if count > 0 {
        let data = Data(buffer.prefix(count))
        emit([
          "id": id, "kind": "data",
          "data": FlutterStandardTypedData(bytes: data),
        ])
      } else if count == 0 {
        if running { emit(["id": id, "kind": "done"]) }
        return
      } else {
        if errno == EINTR { continue }
        if running {
          emit([
            "id": id, "kind": "error",
            "message": "recv failed: \(String(cString: strerror(errno)))",
          ])
        }
        return
      }
    }
  }

  func send(_ data: Data) {
    sendLock.lock()
    defer { sendLock.unlock() }
    guard fd >= 0 else { return }
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var offset = 0
      while offset < data.count {
        let sent = Darwin.send(fd, base + offset, data.count - offset, 0)
        if sent <= 0 { return }
        offset += sent
      }
    }
  }

  func close() {
    running = false
    if fd >= 0 {
      shutdown(fd, SHUT_RDWR)
      Darwin.close(fd)
      fd = -1
    }
  }
}
