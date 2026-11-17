/// DTCP-IP playback engine (Phase 5, plan 26): HEAD -> AKE ->
/// loopback proxy -> player. Enabled only when the user has
/// imported their own credential pair; without a pair, starting
/// playback throws a validation error whose detail the UI turns
/// into import guidance.
library;

import '../diagnostics.dart';
import '../dtcp/ake.dart';
import '../dtcp/credential_store.dart';
import '../dtcp/dtcp_crypto.dart';
import '../dtcp/dtcp_proxy.dart';
import '../errors.dart';
import '../models/title.dart';
import 'interfaces.dart';

class DtcpPlaybackEngine implements PlaybackEngine {
  DtcpPlaybackEngine({
    required this.credentialStore,
    required SrmStore srmStore,
    this.diag = const DiagLog.none(),
    AkeConnectionFactory? akeConnectionFactory,
    AkeClient Function(DeviceCredentials credentials)? clientFactory,
    DtcpMediaFetcher Function()? fetcherFactory,
  }) : _clientFactory =
           clientFactory ??
           ((credentials) => akeConnectionFactory == null
               ? AkeClient(
                   credentials: credentials,
                   srmStore: srmStore,
                   diag: diag,
                 )
               : AkeClient(
                   credentials: credentials,
                   srmStore: srmStore,
                   diag: diag,
                   connectionFactory: akeConnectionFactory,
                 )),
       _fetcherFactory =
           fetcherFactory ?? (() => DtcpMediaFetcher(diag: diag));

  final CredentialStore credentialStore;

  /// Diagnostics sink (plan 28), categories playback/network/ake.
  final DiagLog diag;
  final AkeClient Function(DeviceCredentials credentials) _clientFactory;
  final DtcpMediaFetcher Function() _fetcherFactory;

  /// The engine itself is implemented; whether a credential pair
  /// has been imported is checked asynchronously in [startPlayback].
  @override
  bool get isSupported => true;

  Future<bool> get hasCredentials => credentialStore.hasCredentials;

  @override
  Future<PlaybackSession> startPlayback(
    RecordedTitle title,
    TitleRes res,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = 'credentials';
    AkeSession? session;
    final fetcher = _fetcherFactory();
    try {
      diag(DiagCategory.playback, 'start: credentials -> HEAD -> AKE -> proxy');
      final credentials = await credentialStore.load();
      if (credentials == null) {
        throw NasneError.validation(
          'dtcp:playback',
          'DTCP-IP の資格情報がインポートされていません。設定画面の'
              '「DTCP-IP 資格情報」から、ご自身の対応機器のペアをインポートしてください。',
        );
      }
      final contentUrl = Uri.parse(res.url);
      stage = 'head';
      final (host, port) = await fetcher.akeEndpoint(contentUrl);
      diag(
        DiagCategory.playback,
        'stage head ok (${stopwatch.elapsedMilliseconds} ms)',
      );
      stage = 'ake';
      final client = _clientFactory(credentials);
      session = await client.connect(host, port);
      diag(
        DiagCategory.playback,
        'stage ake ok (${stopwatch.elapsedMilliseconds} ms)',
      );
      // The reference client returns from authenticate() only with
      // the first exchange key in hand (plan 28). Waiting here
      // keeps a missing key a start failure with a named stage,
      // instead of a stall inside the player.
      stage = 'exchange key';
      final label = await session.waitFirstExchangeKey();
      diag(
        DiagCategory.playback,
        'stage exchange key ok, label $label '
        '(${stopwatch.elapsedMilliseconds} ms)',
      );
      stage = 'proxy';
      final proxy = await DtcpProxy.start(
        contentUrl: contentUrl,
        session: session,
        fetcher: fetcher,
        diag: diag,
      );
      diag(
        DiagCategory.playback,
        'playback ready at ${proxy.uri} '
        '(${stopwatch.elapsedMilliseconds} ms)',
      );
      return _DtcpPlaybackSession(proxy, session, fetcher);
    } catch (e) {
      diag(DiagCategory.playback, 'failed at stage "$stage": $e');
      if (session != null) await session.close();
      fetcher.close();
      rethrow;
    }
  }
}

class _DtcpPlaybackSession implements PlaybackSession {
  _DtcpPlaybackSession(this._proxy, this._akeSession, this._fetcher);

  final DtcpProxy _proxy;
  final AkeSession _akeSession;
  final DtcpMediaFetcher _fetcher;
  bool _stopped = false;

  @override
  Uri get mediaUri => _proxy.uri;

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _proxy.stop();
    await _akeSession.close();
    _fetcher.close();
  }
}
