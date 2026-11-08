import '../media_browser/media_browser_client.dart';
import '../media_server/playback_models.dart';
import 'jellyfin_playback_session.dart';

class JellyfinClient extends MediaBrowserClient {
  JellyfinClient({required super.server, super.dio})
    : super(headers: _headers(server.apiKey));

  @override
  bool get isConfigured => server.apiKey.isNotEmpty;

  @override
  Map<String, String> get authHeaders => _headers(server.apiKey);

  static Map<String, String> _headers(String apiKey) => {
    'Authorization':
        'MediaBrowser Token="$apiKey", Client="Sakuga", Device="Sakuga", DeviceId="sakuga", Version="0.1.0"',
  };

  @override
  bool acceptsSession(dynamic session) => session is JellyfinPlaybackSession;

  @override
  JellyfinPlaybackSession createSession({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required PlayMethod playMethod,
  }) => JellyfinPlaybackSession(
    itemId: itemId,
    mediaSourceId: mediaSourceId,
    playSessionId: playSessionId,
    playMethod: playMethod,
  );
}
