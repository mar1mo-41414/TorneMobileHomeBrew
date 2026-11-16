/// DTCP-IP Authentication and Key Exchange (AKE), sink side.
///
/// Port of pydtcpip's `dtcp/ake.py` (MIT, (c) tsukumijima): control
/// frame layout, command set, Full Authentication handshake, RTT
/// measurement and SRM update handling. Deviations from the
/// reference implementation are listed in plan 26.5: the transport
/// is an injectable [AkeConnection] (the IP TTL 3 requirement of the
/// reference cannot be expressed with dart:io), and the SRM is
/// persisted through a callback instead of a database.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../errors.dart';
import 'dtcp_crypto.dart';
import 'srm.dart';

/// AKE command values on the wire (pydtcpip's `AKECommand`).
abstract final class AkeCommands {
  static const int challenge = 0x01;
  static const int response = 0x02;
  static const int exchangeKey = 0x03;
  static const int srmUpdate = 0x04;
  static const int rttSetup = 0x11;
  static const int rttTest = 0x12;
  static const int rttReady = 0x91;
  static const int rttVerify = 0x92;
}

const int _frameControl = 0x0;
const int _frameAccepted = 0x9;
const int _procedureFullAuth = 0x04;
const int _keyTypeAes128 = 0x08;
const int _roleSource = 0x01;
const int _roleSink = 0x02;

/// An 11-byte-header AKE control frame.
class ControlFrame {
  ControlFrame({
    required this.command,
    required this.payload,
    this.isResponse = false,
    this.procedure = _procedureFullAuth,
    this.keyType = _keyTypeAes128,
    this.isSource = false,
    this.label = 0,
    this.status = 0,
  });

  final int command;
  final Uint8List payload;
  final bool isResponse;
  final int procedure;
  final int keyType;
  final bool isSource;
  final int label;
  final int status;

  Uint8List encode() {
    final totalLength = payload.length + 8;
    final out = Uint8List(11 + payload.length);
    out[0] = 0x01;
    out[1] = (totalLength >> 8) & 0xFF;
    out[2] = totalLength & 0xFF;
    out[3] = isResponse ? _frameAccepted : _frameControl;
    out[4] = 0;
    out[5] = command;
    out[6] = procedure;
    out[7] = keyType;
    out[8] = isSource ? _roleSource : _roleSink;
    out[9] = label;
    out[10] = status;
    out.setRange(11, out.length, payload);
    return out;
  }

  /// Parses one frame from the front of [data]; returns the frame
  /// and the number of bytes consumed, or null when more bytes are
  /// needed. Throws on a malformed header.
  static (ControlFrame, int)? tryParse(Uint8List data) {
    if (data.length < 11) return null;
    if (data[0] != 0x01 || data[4] != 0) {
      throw NasneError.parse('dtcp:ake', cause: 'invalid AKE frame header');
    }
    final totalLength = (data[1] << 8) | data[2];
    final frameLength = totalLength + 3;
    if (totalLength < 8 || data.length < frameLength) return null;
    final frameType = data[3] & 0x0F;
    if (frameType != _frameControl && frameType != _frameAccepted) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'unknown AKE frame type 0x${frameType.toRadixString(16)}',
      );
    }
    return (
      ControlFrame(
        command: data[5],
        payload: Uint8List.fromList(data.sublist(11, frameLength)),
        isResponse: frameType == _frameAccepted,
        procedure: data[6],
        keyType: data[7],
        isSource: data[8] == _roleSource,
        label: data[9],
        status: data[10] & 0x0F,
      ),
      frameLength,
    );
  }
}

/// Transport for AKE frames. The default factory opens a TCP socket;
/// the IP TTL of 3 that the reference implementation sets cannot be
/// expressed with dart:io, so the factory is kept replaceable
/// (plan 26.5).
abstract interface class AkeConnection {
  Stream<Uint8List> get incoming;
  void send(Uint8List bytes);
  Future<void> close();
}

typedef AkeConnectionFactory = Future<AkeConnection> Function(
  String host,
  int port,
);

class _SocketAkeConnection implements AkeConnection {
  _SocketAkeConnection(this._socket);
  final Socket _socket;

  @override
  Stream<Uint8List> get incoming => _socket;

  @override
  void send(Uint8List bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.flush().catchError((_) {});
    _socket.destroy();
  }
}

Future<AkeConnection> socketAkeConnectionFactory(String host, int port) async {
  final socket = await Socket.connect(
    host,
    port,
    timeout: const Duration(seconds: 10),
  );
  return _SocketAkeConnection(socket);
}

/// Supplies and persists the current SRM (plan 26.4: signed public
/// data, kept in the regular store).
abstract interface class SrmStore {
  Future<Srm?> load();
  Future<void> save(Uint8List raw, Srm srm);
  Future<Uint8List?> loadRaw();
}

/// An established AKE session: holds the exchange keys in memory
/// only. Keys are never persisted (plan 26.4).
class AkeSession {
  AkeSession._(this._connection, this._client);

  final AkeConnection _connection;
  final AkeClient _client;

  /// The currently active exchange key label, if any.
  int? get exchangeKeyLabel => _client.exchangeKeyLabel;

  /// Waits for a key with [label] to arrive via EXCHANGE_KEY.
  Future<Uint8List> waitExchangeKey(int label, {Duration? timeout}) =>
      _client.waitExchangeKey(label, timeout: timeout);

  Future<void> close() => _connection.close();
}

/// Sink-side AKE client implementing Full Authentication against a
/// DTCP-IP source (the nasne).
class AkeClient {
  AkeClient({
    required this.credentials,
    required this.srmStore,
    this.connectionFactory = socketAkeConnectionFactory,
    this.authorityKeys = const [],
    Uint8List Function(int length)? randomBytes,
    BigInt Function()? ephemeralScalar,
  }) : _randomBytes = randomBytes ?? _secureRandomBytes,
       _ephemeralScalar = ephemeralScalar ?? generateEphemeralScalar;

  final DeviceCredentials credentials;
  final SrmStore srmStore;
  final AkeConnectionFactory connectionFactory;
  final Uint8List Function(int length) _randomBytes;
  final BigInt Function() _ephemeralScalar;

  /// DTLA authority keys for certificate / SRM verification;
  /// empty = the real DTLA keys. Non-empty only in tests.
  final List<Uint8List> authorityKeys;

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  int? _exchangeKeyLabel;
  final Map<int, Completer<Uint8List>> _keyWaiters = {};
  final Map<int, Uint8List> _exchangeKeys = {};

  int? get exchangeKeyLabel => _exchangeKeyLabel;

  Future<Uint8List> waitExchangeKey(int label, {Duration? timeout}) {
    final existing = _exchangeKeys[label];
    if (existing != null) return Future.value(existing);
    final completer = _keyWaiters.putIfAbsent(
      label,
      () => Completer<Uint8List>(),
    );
    final future = completer.future;
    return timeout == null ? future : future.timeout(timeout);
  }

  /// Runs the full handshake and returns the live session. The
  /// session's message loop keeps running until [AkeSession.close].
  Future<AkeSession> connect(String host, int port) async {
    final connection = await connectionFactory(host, port);
    final reader = _FrameReader(connection);
    try {
      final authKey = await _authenticate(reader);
      final session = AkeSession._(connection, this);
      // The post-authentication loop (RTT / EXCHANGE_KEY /
      // SRM_UPDATE) runs in the background; failures close the
      // session silently from the player's perspective.
      unawaited(_messageLoop(reader, authKey).catchError((_) {}));
      return session;
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  Future<Uint8List> _authenticate(_FrameReader reader) async {
    var srm = await srmStore.load();
    final myNonce = _randomBytes(16);

    // CHALLENGE: nonce || my certificate.
    await reader.send(
      ControlFrame(
        command: AkeCommands.challenge,
        payload: Uint8List.fromList([...myNonce, ...credentials.certificate]),
      ),
    );
    var frame = await reader.next();
    _expectAccepted(frame, AkeCommands.challenge);

    // The source's CHALLENGE.
    frame = await reader.next();
    if (frame.isResponse ||
        frame.command != AkeCommands.challenge ||
        frame.payload.length != 104) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'expected the source CHALLENGE frame',
      );
    }
    final sourceNonce = frame.payload.sublist(0, 16);
    final sourceCert = frame.payload.sublist(16);
    final sourcePublicKey = verifyCertificate(
      sourceCert,
      authorityKeys: authorityKeys,
    );
    _peerCertificate = Uint8List.fromList(sourceCert);
    if (srm != null) {
      if (srm.isRevoked(deviceIdOf(sourceCert))) {
        throw NasneError.parse(
          'dtcp:ake',
          cause: 'the source device is revoked by the SRM',
        );
      }
      if (srm.isRevoked(credentials.deviceId)) {
        throw NasneError.parse(
          'dtcp:ake',
          cause: 'this device is revoked by the SRM',
        );
      }
    }

    await reader.send(
      ControlFrame(
        command: AkeCommands.challenge,
        payload: Uint8List(0),
        isResponse: true,
      ),
    );

    // The source's RESPONSE.
    frame = await reader.next();
    if (frame.isResponse ||
        frame.command != AkeCommands.response ||
        frame.payload.length != 83) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'expected the source RESPONSE frame',
      );
    }
    final sourceEphemeral = frame.payload.sublist(0, 40);
    final sourceEphemeralPoint = EcPoint.fromBytes(sourceEphemeral);
    if (sourceEphemeralPoint == null) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'the source ephemeral key is invalid',
      );
    }
    _peerSrmVersion = (frame.payload[40] << 8) | frame.payload[41];
    _peerSrmGeneration = frame.payload[42] & 0x0F;
    _peerMaxSrmGeneration = _peerCertificate![1] >> 4;
    if (_peerSrmGeneration > _peerMaxSrmGeneration) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'the source SRM generation exceeds its maximum',
      );
    }
    final sourceSignature = frame.payload.sublist(43);
    final signedData = Uint8List.fromList([
      ...myNonce,
      ...frame.payload.sublist(0, 43),
    ]);
    if (!ecdsaVerify(sourcePublicKey, signedData, sourceSignature)) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'the source signature verification failed',
      );
    }

    // ECDH: the authentication key is the last 12 bytes of the
    // shared point's x coordinate.
    final ephemeral = _ephemeralScalar();
    final ephemeralPublic = DtcpCurve.generator * ephemeral;
    final shared = ecdhSharedSecret(ephemeral, sourceEphemeralPoint);
    final authKey = Uint8List.fromList(shared.sublist(8));

    await reader.send(
      ControlFrame(
        command: AkeCommands.response,
        payload: Uint8List(0),
        isResponse: true,
      ),
    );

    // My RESPONSE: ephemeral public key || SRM version/generation
    // || deterministic signature over (source nonce || payload).
    final mySrm = await srmStore.load();
    final responseData = Uint8List.fromList([
      ...ephemeralPublic.toBytes(),
      ((mySrm?.version ?? 0) >> 8) & 0xFF,
      (mySrm?.version ?? 0) & 0xFF,
      mySrm?.generation ?? 0,
    ]);
    final signature = ecdsaSignDeterministic(
      credentials.privateScalar,
      Uint8List.fromList([...sourceNonce, ...responseData]),
    );
    await reader.send(
      ControlFrame(
        command: AkeCommands.response,
        payload: Uint8List.fromList([...responseData, ...signature]),
      ),
    );
    frame = await reader.next();
    _expectAccepted(frame, AkeCommands.response);
    return authKey;
  }

  /// The source's certificate and SRM coordinates, retained from
  /// the handshake for SRM_UPDATE checks and SRM forwarding.
  Uint8List? _peerCertificate;
  int _peerSrmVersion = 0;
  int _peerSrmGeneration = 0;
  int _peerMaxSrmGeneration = 0;

  void _expectAccepted(ControlFrame frame, int command) {
    if (!frame.isResponse || frame.command != command || frame.status != 0) {
      throw NasneError.parse(
        'dtcp:ake',
        cause:
            'the source rejected the AKE step '
            '(command 0x${command.toRadixString(16)})',
      );
    }
  }

  Future<void> _messageLoop(_FrameReader reader, Uint8List authKey) async {
    // RTT MACs are precomputed at RTT_SETUP time because the
    // source bounds the measurement round trip (7 ms in the
    // reference implementation's notes).
    final rttBase = bytesToBigInt(sha1Bytes([...authKey, ...authKey]));
    Uint8List? rttExpectedTest;
    Uint8List? rttTestResponse;
    Uint8List? rttVerifyResponse;
    Uint8List? receivedRttTest;

    while (true) {
      final frame = await reader.next();
      switch (frame.command) {
        case AkeCommands.rttReady:
          if (frame.isResponse) {
            // The source accepted our RTT_READY; wait for the next
            // request (reference behaviour).
            continue;
          }
          await reader.send(
            ControlFrame(
              command: AkeCommands.rttReady,
              payload: Uint8List(0),
              isResponse: true,
            ),
          );
          await reader.send(
            ControlFrame(command: AkeCommands.rttReady, payload: Uint8List(0)),
          );
        case AkeCommands.rttSetup:
          if (frame.isResponse || frame.payload.length != 2) {
            throw NasneError.parse(
              'dtcp:ake',
              cause: 'invalid RTT_SETUP frame',
            );
          }
          final counter = (frame.payload[0] << 8) | frame.payload[1];
          final digest = sha1Bytes(
            bigIntToBytes((rttBase + BigInt.from(counter)) % _twoPow160, 20),
          );
          rttExpectedTest = Uint8List.fromList(digest.sublist(0, 10));
          rttTestResponse = Uint8List.fromList(digest.sublist(10));
          final verifyDigest = sha1Bytes(
            bigIntToBytes(
              (rttBase + BigInt.from(counter) + BigInt.one) % _twoPow160,
              20,
            ),
          );
          rttVerifyResponse = Uint8List.fromList(verifyDigest.sublist(0, 10));
          // The reference echoes the counter as the acceptance.
          await reader.send(
            ControlFrame(
              command: AkeCommands.rttSetup,
              payload: frame.payload,
              isResponse: true,
            ),
          );
        case AkeCommands.rttTest:
          if (frame.isResponse ||
              rttExpectedTest == null ||
              frame.payload.length != 10) {
            throw NasneError.parse('dtcp:ake', cause: 'invalid RTT_TEST frame');
          }
          receivedRttTest = frame.payload;
          await reader.send(
            ControlFrame(
              command: AkeCommands.rttTest,
              payload: rttTestResponse!,
              isResponse: true,
            ),
          );
        case AkeCommands.rttVerify:
          if (frame.isResponse ||
              rttExpectedTest == null ||
              receivedRttTest == null ||
              !_bytesEqual(receivedRttTest, rttExpectedTest)) {
            throw NasneError.parse(
              'dtcp:ake',
              cause: 'RTT verification failed',
            );
          }
          await reader.send(
            ControlFrame(
              command: AkeCommands.rttVerify,
              payload: rttVerifyResponse!,
              isResponse: true,
            ),
          );
        case AkeCommands.exchangeKey:
          if (frame.isResponse || frame.payload.length != 14) {
            throw NasneError.parse(
              'dtcp:ake',
              cause: 'invalid EXCHANGE_KEY frame',
            );
          }
          final label = frame.payload[0];
          final masked = frame.payload.sublist(2);
          final key = Uint8List(12);
          for (var i = 0; i < 12; i++) {
            key[i] = masked[i] ^ authKey[i];
          }
          _exchangeKeys[label] = key;
          _exchangeKeyLabel = label;
          _keyWaiters.remove(label)?.complete(key);
          await reader.send(
            ControlFrame(
              command: AkeCommands.exchangeKey,
              payload: Uint8List(0),
              isResponse: true,
              label: label,
            ),
          );
          await _forwardSrmIfNewer(reader);
        case AkeCommands.srmUpdate:
          if (frame.isResponse) {
            throw NasneError.parse(
              'dtcp:ake',
              cause: 'unexpected SRM_UPDATE response frame',
            );
          }
          await _handleSrmUpdate(reader, frame.payload);
        default:
          throw NasneError.parse(
            'dtcp:ake',
            cause:
                'unsupported AKE command '
                '0x${frame.command.toRadixString(16)}',
          );
      }
    }
  }

  Future<void> _handleSrmUpdate(_FrameReader reader, Uint8List payload) async {
    final newSrm = Srm.parse(payload, authorityKeys: authorityKeys);
    final current = await srmStore.load();
    final Srm effective;
    if (current == null || newSrm.isNewerThan(current)) {
      // A newer SRM is retained even if it revokes a party (the
      // reference behaviour); the checks below then apply it.
      await srmStore.save(payload, newSrm);
      effective = newSrm;
    } else {
      effective = current;
    }
    final peer = _peerCertificate;
    if (peer != null && effective.isRevoked(deviceIdOf(peer))) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'the source device is revoked by the SRM',
      );
    }
    if (effective.isRevoked(credentials.deviceId)) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'this device is revoked by the SRM',
      );
    }
    await reader.send(
      ControlFrame(
        command: AkeCommands.srmUpdate,
        payload: Uint8List(0),
        isResponse: true,
      ),
    );
  }

  /// After an EXCHANGE_KEY, a newer local SRM is forwarded to the
  /// source (reference behaviour). The update frame carries key
  /// type 0: the source rejects a specified key type here.
  Future<void> _forwardSrmIfNewer(_FrameReader reader) async {
    final localSrm = await srmStore.load();
    if (localSrm == null || _peerCertificate == null) return;
    final isLocalNewer =
        localSrm.version > _peerSrmVersion ||
        (localSrm.version == _peerSrmVersion &&
            _peerSrmGeneration < _peerMaxSrmGeneration &&
            localSrm.generation > _peerSrmGeneration);
    if (!isLocalNewer) return;
    var sendData = localSrm.data;
    if (localSrm.generation > _peerMaxSrmGeneration) {
      // Send only the first generation part, retaining the signed
      // header, to a peer limited to generation 0.
      final firstLength = (sendData[4] << 8) | sendData[5];
      sendData = Uint8List.fromList(sendData.sublist(0, 4 + firstLength));
    }
    await reader.send(
      ControlFrame(
        command: AkeCommands.srmUpdate,
        payload: sendData,
        keyType: 0,
      ),
    );
    final accepted = await reader.next();
    if (!accepted.isResponse ||
        accepted.command != AkeCommands.srmUpdate ||
        accepted.status != 0) {
      throw NasneError.parse(
        'dtcp:ake',
        cause: 'the source did not accept the SRM update',
      );
    }
  }

  static final BigInt _twoPow160 = BigInt.one << 160;

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Buffers a connection's byte stream into control frames.
class _FrameReader {
  _FrameReader(this._connection) {
    _connection.incoming.listen(
      (chunk) {
        _buffer.addAll(chunk);
        _drain();
      },
      onError: (Object e) => _fail(e),
      onDone: () => _fail(
        NasneError.unreachable('dtcp:ake', cause: 'the AKE connection closed'),
      ),
    );
  }

  final AkeConnection _connection;
  final List<int> _buffer = [];
  final List<Completer<ControlFrame>> _waiters = [];
  final List<ControlFrame> _frames = [];
  Object? _error;

  void _drain() {
    while (true) {
      final parsed = ControlFrame.tryParse(Uint8List.fromList(_buffer));
      if (parsed == null) return;
      final (frame, consumed) = parsed;
      _buffer.removeRange(0, consumed);
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(frame);
      } else {
        _frames.add(frame);
      }
    }
  }

  void _fail(Object error) {
    _error ??= error;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _waiters.clear();
  }

  Future<void> send(ControlFrame frame) async {
    _connection.send(frame.encode());
  }

  Future<ControlFrame> next() {
    if (_frames.isNotEmpty) return Future.value(_frames.removeAt(0));
    if (_error != null) return Future.error(_error!);
    final completer = Completer<ControlFrame>();
    _waiters.add(completer);
    return completer.future;
  }
}
