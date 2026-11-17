/// Native AKE transport with IP TTL 3 (plan 28).
///
/// The reference DTCP-IP client sets IP TTL 3 on the AKE socket
/// (the DTCP proximity requirement; its comment notes some
/// recorders drop the connection right after CHALLENGE when the
/// TTL is higher) and enables TCP_NODELAY. dart:io can do the
/// latter but not the former, so on iOS/Android/macOS/Linux the AKE
/// socket is a platform-channel native socket that sets both via
/// setsockopt. On other platforms — and if the native channel is
/// unavailable — this falls back to the dart:io transport (which
/// sets TCP_NODELAY only). Beware: the nasne refuses the AKE TCP
/// connection itself (RST) when the TTL is above 3 (plan 39.5),
/// so the dart:io fallback cannot authenticate against it; it
/// exists for graceful degradation and shows up in the log.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/core.dart';

const _methodChannel = MethodChannel('com.markun.tmhb/ake_socket');
const _eventChannel = EventChannel('com.markun.tmhb/ake_socket_events');

/// An [AkeConnectionFactory] that prefers the native TTL-3 socket
/// on the platforms that have one (iOS / Android / macOS / Linux).
Future<AkeConnection> nativeAkeConnectionFactory(
  String host,
  int port, {
  DiagLog diag = const DiagLog.none(),
}) async {
  if (!Platform.isAndroid &&
      !Platform.isIOS &&
      !Platform.isMacOS &&
      !Platform.isLinux) {
    diag(
      DiagCategory.ake,
      'ake transport: dart socket (no native socket on this platform)',
    );
    return socketAkeConnectionFactory(host, port);
  }
  _NativeAkeHub.ensureSubscribed();
  final id = _NativeAkeHub.nextId++;
  final connection = _NativeAkeConnection(id);
  _NativeAkeHub.connections[id] = connection;
  try {
    await _methodChannel
        .invokeMethod<void>('connect', {'id': id, 'host': host, 'port': port})
        .timeout(const Duration(seconds: 12));
    diag(DiagCategory.ake, 'ake transport: native socket, ip ttl 3');
    return connection;
  } on MissingPluginException {
    _NativeAkeHub.connections.remove(id);
    diag(
      DiagCategory.ake,
      'ake transport: dart socket (native channel unavailable)',
    );
    return socketAkeConnectionFactory(host, port);
  } on PlatformException catch (e) {
    _NativeAkeHub.connections.remove(id);
    throw NasneError.unreachable(
      'dtcp:ake',
      cause: 'native AKE socket failed: ${e.code} ${e.message ?? ''}'.trim(),
    );
  } on TimeoutException {
    _NativeAkeHub.connections.remove(id);
    unawaited(
      _methodChannel
          .invokeMethod<void>('close', {'id': id})
          .catchError((_) {}),
    );
    throw NasneError.unreachable(
      'dtcp:ake',
      cause: 'native AKE socket connect timed out',
    );
  }
}

/// Routes native socket events to their connections by id.
abstract final class _NativeAkeHub {
  static final Map<int, _NativeAkeConnection> connections = {};
  static int nextId = 1;
  static StreamSubscription<dynamic>? _subscription;

  static void ensureSubscribed() {
    _subscription ??= _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        final connection = connections[event['id']];
        if (connection == null) return;
        switch (event['kind']) {
          case 'data':
            final data = event['data'];
            if (data is Uint8List) connection._addData(data);
          case 'error':
            connection._addError('${event['message'] ?? 'socket error'}');
          case 'done':
            connection._closeFromNative();
        }
      },
      onError: (_) {},
    );
  }
}

class _NativeAkeConnection implements AkeConnection {
  _NativeAkeConnection(this._id);

  final int _id;
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>();
  bool _closed = false;

  @override
  Stream<Uint8List> get incoming => _controller.stream;

  @override
  void send(Uint8List bytes) {
    if (_closed) return;
    unawaited(
      _methodChannel
          .invokeMethod<void>('send', {'id': _id, 'data': bytes})
          .catchError((_) {}),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _NativeAkeHub.connections.remove(_id);
    try {
      await _methodChannel.invokeMethod<void>('close', {'id': _id});
    } catch (_) {}
    await _controller.close();
  }

  void _addData(Uint8List data) {
    if (!_closed) _controller.add(data);
  }

  void _addError(String message) {
    if (_closed) return;
    _controller.addError(
      NasneError.unreachable('dtcp:ake', cause: message),
    );
  }

  void _closeFromNative() {
    if (_closed) return;
    _closed = true;
    _NativeAkeHub.connections.remove(_id);
    unawaited(_controller.close());
  }
}
