/// DTCP-IP playback engine (Phase 5, plan 26): HEAD -> AKE ->
/// loopback proxy -> player. Enabled only when the user has
/// imported their own credential pair; without a pair, starting
/// playback throws a validation error whose detail the UI turns
/// into import guidance.
library;

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
    AkeClient Function(DeviceCredentials credentials)? clientFactory,
    DtcpMediaFetcher Function()? fetcherFactory,
  }) : _clientFactory =
           clientFactory ??
           ((credentials) =>
               AkeClient(credentials: credentials, srmStore: srmStore)),
       _fetcherFactory = fetcherFactory ?? DtcpMediaFetcher.new;

  final CredentialStore credentialStore;
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
    final credentials = await credentialStore.load();
    if (credentials == null) {
      throw NasneError.validation(
        'dtcp:playback',
        'DTCP-IP の資格情報がインポートされていません。設定画面の'
            '「DTCP-IP 資格情報」から、ご自身の対応機器のペアをインポートしてください。',
      );
    }
    final fetcher = _fetcherFactory();
    try {
      final contentUrl = Uri.parse(res.url);
      final (host, port) = await fetcher.akeEndpoint(contentUrl);
      final client = _clientFactory(credentials);
      final session = await client.connect(host, port);
      final proxy = await DtcpProxy.start(
        contentUrl: contentUrl,
        session: session,
        fetcher: fetcher,
      );
      return _DtcpPlaybackSession(proxy, session, fetcher);
    } catch (_) {
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
