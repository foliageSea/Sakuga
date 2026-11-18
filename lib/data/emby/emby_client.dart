import 'package:dio/dio.dart';

import '../media_browser/media_browser_client.dart';
import '../media_browser/media_browser_playback_session.dart';
import '../media_server/playback_models.dart';
import '../media_server/server_profile.dart';
import 'emby_playback_session.dart';
import 'emby_protocol.dart';

class EmbyClient extends MediaBrowserClient {
  EmbyClient({required super.server, Dio? dio})
    : super(
        dio: _configure(server, dio),
        headers: embyAuthHeaders(
          accessToken: server.accessToken,
          deviceId: server.deviceId,
        ),
        emby: true,
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
    client.options.baseUrl = embyApiBaseUrl(server.baseUrl);
    client.options.headers.removeWhere(
      (key, _) =>
          key.toLowerCase() == 'authorization' ||
          key.toLowerCase().startsWith('x-emby-'),
    );
    client.options.headers.addAll(
      embyAuthHeaders(
        accessToken: server.accessToken,
        deviceId: server.deviceId,
      ),
    );
    // Do not forward credentials through an HTTP redirect to another origin.
    client.options.followRedirects = false;
    return client;
  }

  @override
  bool get isConfigured =>
      server.accessToken.isNotEmpty && server.userId.isNotEmpty;
  @override
  String get apiBaseUrl => embyApiBaseUrl(server.baseUrl);
  @override
  String get playbackDeviceId => server.deviceId;
  @override
  Map<String, String> get authHeaders => embyAuthHeaders(
    accessToken: server.accessToken,
    deviceId: server.deviceId,
  );
  @override
  String absoluteUrl(String path) {
    final resolved = resolveEmbyUrl(server.baseUrl, path);
    if (embySameOrigin(apiBaseUrl, resolved)) return resolved;
    final uri = Uri.parse(resolved);
    final query = Map<String, String>.of(uri.queryParameters);
    final originalLength = query.length;
    query.removeWhere(
      (key, value) =>
          value == server.accessToken &&
          const {
            'api_key',
            'apikey',
            'access_token',
            'x-emby-token',
          }.contains(key.toLowerCase()),
    );
    if (query.length == originalLength) return resolved;
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  @override
  String? externalSubtitlePath(
    Map<String, dynamic> stream,
    Map<String, dynamic> source,
    String itemId,
  ) {
    final provided = super.externalSubtitlePath(stream, source, itemId);
    if (provided != null && provided.isNotEmpty) return provided;
    final codec = stream['Codec']?.toString().toLowerCase();
    final format = switch (codec) {
      'srt' || 'subrip' => 'srt',
      'vtt' || 'webvtt' => 'vtt',
      'ass' => 'ass',
      'ssa' => 'ssa',
      _ => null,
    };
    final sourceId = source['Id'];
    final index = stream['Index'];
    if (format == null ||
        sourceId is! String ||
        sourceId.isEmpty ||
        index is! int ||
        index < 0) {
      return null;
    }
    return '/Videos/${Uri.encodeComponent(itemId)}/${Uri.encodeComponent(sourceId)}/Subtitles/$index/0/Stream.$format?CopyTimestamps=true';
  }

  @override
  Future<PlaybackSource> playbackSource(
    String userId,
    String itemId, {
    Duration? startPosition,
    int? maxStreamingBitrate,
    int? maxVideoHeight,
  }) async {
    final source = await super.playbackSource(
      userId,
      itemId,
      startPosition: startPosition,
      maxStreamingBitrate: maxStreamingBitrate,
      maxVideoHeight: maxVideoHeight,
    );
    // mpv installs media headers globally, including redirects, HLS segments
    // and sub-add. Authenticate server URLs themselves, never its global headers.
    return PlaybackSource(
      url: _authenticatedResourceUrl(source.url),
      headers: playbackHeaders(source.url, source.headers),
      session: source.session,
      startPosition: source.startPosition,
      initialPosition: source.initialPosition,
      positionOffset: source.positionOffset,
      subtitles: source.subtitles,
      playMethod: source.playMethod,
    );
  }

  @override
  Map<String, String> playbackHeaders(
    String url,
    Map<String, String> headers,
  ) => {
    for (final entry in headers.entries)
      if (!_credentialHeader(entry.key)) entry.key: entry.value,
  };
  static bool _credentialHeader(String key) =>
      key.toLowerCase() == 'authorization' ||
      key.toLowerCase().startsWith('x-emby-') ||
      key.toLowerCase() == 'cookie';
  @override
  String subtitleUrl(String path) {
    return _authenticatedResourceUrl(absoluteUrl(path));
  }

  String _authenticatedResourceUrl(String url) {
    if (!embySameOrigin(apiBaseUrl, url)) return url;
    final uri = Uri.parse(url);
    if (uri.queryParameters.keys.any(
      (key) => const {
        'api_key',
        'apikey',
        'x-emby-token',
        'access_token',
      }.contains(key.toLowerCase()),
    )) {
      return url;
    }
    // Append without rebuilding existing query parameters (signed URLs may
    // contain duplicate keys and significant percent-encoding).
    final token = 'api_key=${Uri.encodeQueryComponent(server.accessToken)}';
    return uri
        .replace(
          query: uri.hasQuery && uri.query.isNotEmpty
              ? '${uri.query}&$token'
              : token,
        )
        .toString();
  }

  @override
  bool acceptsSession(MediaBrowserPlaybackSession session) =>
      session is EmbyPlaybackSession;
  @override
  EmbyPlaybackSession createSession({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required PlayMethod playMethod,
  }) => EmbyPlaybackSession(
    itemId: itemId,
    mediaSourceId: mediaSourceId,
    playSessionId: playSessionId,
    playMethod: playMethod,
  );
}
