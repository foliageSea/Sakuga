import 'package:dio/dio.dart';

import '../media_browser/media_browser_client.dart';
import '../media_server/server_profile.dart';
import '../media_server/playback_models.dart';
import 'jellyfin_playback_session.dart';
import 'jellyfin_protocol.dart';

class JellyfinClient extends MediaBrowserClient {
  JellyfinClient({required super.server, Dio? dio})
    : super(dio: _configure(server, dio), headers: _headers(server));

  static Map<String, String> _headers(ServerProfile server) =>
      jellyfinAuthHeaders(
        token: server.usesAccount ? server.accessToken : server.apiKey,
        deviceId: server.deviceId.isEmpty ? 'sakuga' : server.deviceId,
        username: server.usesAccount ? server.username : '',
      );

  static Dio _configure(ServerProfile server, Dio? dio) {
    final client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 10),
          ),
        );
    client.options.baseUrl = server.baseUrl;
    client.options.headers = {
      for (final entry in client.options.headers.entries)
        if (entry.key.toLowerCase() != 'authorization' &&
            !entry.key.toLowerCase().startsWith('x-emby-'))
          entry.key: entry.value,
      ..._headers(server),
    };
    client.options.followRedirects = false;
    return client;
  }

  @override
  bool get isConfigured => server.usesAccount
      ? server.accessToken.isNotEmpty && server.userId.isNotEmpty
      : server.apiKey.isNotEmpty;

  @override
  Map<String, String> get authHeaders => _headers(server);

  @override
  String get playbackDeviceId => jellyfinDeviceIdentity(
    server.deviceId.isEmpty ? 'sakuga' : server.deviceId,
    server.usesAccount ? server.username : '',
  );

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
