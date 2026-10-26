import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import 'jellyfin_models.dart';
import 'server_profile.dart';

class JellyfinClient {
  JellyfinClient({required this.server, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: server.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 10),
              headers: _headers(server.apiKey),
            ),
          );

  final ServerProfile server;
  final Dio _dio;

  /// Fields shared by every browse request: scraped image metadata plus the
  /// per-user playback state.
  static const _itemFields = 'PrimaryImageAspectRatio,ImageTags,UserData';

  Map<String, String> get authHeaders => _headers(server.apiKey);

  /// Negotiates a playable stream for [itemId].
  ///
  /// mpv supports the common Jellyfin containers and codecs directly. The
  /// server can still return a transcoding URL when the source is not suitable
  /// for direct playback; that URL must be used as-is.
  Future<JellyfinPlaybackSource> playbackSource(
    String userId,
    String itemId, {
    int startTimeTicks = 0,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/Items/$itemId/PlaybackInfo',
      queryParameters: {'userId': userId},
      data: {
        'UserId': userId,
        'StartTimeTicks': startTimeTicks,
        'MaxStreamingBitrate': 120000000,
        'EnableDirectPlay': true,
        'EnableDirectStream': true,
        'EnableTranscoding': true,
        'AllowVideoStreamCopy': true,
        'AllowAudioStreamCopy': true,
        'DeviceProfile': _mpvDeviceProfile,
      },
    );
    final data = response.data ?? const <String, dynamic>{};
    final errorCode = data['ErrorCode'] as String?;
    if (errorCode != null && errorCode.isNotEmpty) {
      throw AppException(FailureKind.server, errorCode);
    }

    final sources = (data['MediaSources'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final source = _preferredSource(sources);
    if (source == null) {
      throw const AppException(FailureKind.invalidData, 'No playable source');
    }

    final mediaSourceId = source['Id'] as String? ?? '';
    final playSessionId = data['PlaySessionId'] as String? ?? '';
    final requiredHeaders = source['RequiredHttpHeaders'];
    final headers = <String, String>{
      ...authHeaders,
      if (requiredHeaders is Map)
        for (final entry in requiredHeaders.entries)
          entry.key.toString(): entry.value.toString(),
    };
    final subtitles = _subtitleSources(source);

    if (source['SupportsDirectPlay'] == true) {
      return JellyfinPlaybackSource(
        url: _url(
          '/Videos/$itemId/stream',
          queryParameters: {
            'static': 'true',
            if (mediaSourceId.isNotEmpty) 'mediaSourceId': mediaSourceId,
            if (playSessionId.isNotEmpty) 'playSessionId': playSessionId,
          },
        ),
        headers: headers,
        startPosition: _durationFromTicks(startTimeTicks),
        subtitles: subtitles,
      );
    }

    final transcodingUrl = source['TranscodingUrl'] as String?;
    if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
      return JellyfinPlaybackSource(
        url: _absoluteUrl(transcodingUrl),
        headers: headers,
        subtitles: subtitles,
      );
    }

    if (source['SupportsDirectStream'] == true) {
      return JellyfinPlaybackSource(
        url: _url(
          '/Videos/$itemId/stream',
          queryParameters: {
            'static': 'false',
            if (mediaSourceId.isNotEmpty) 'mediaSourceId': mediaSourceId,
            if (playSessionId.isNotEmpty) 'playSessionId': playSessionId,
          },
        ),
        headers: headers,
        startPosition: _durationFromTicks(startTimeTicks),
        subtitles: subtitles,
      );
    }

    throw const AppException(FailureKind.invalidData, 'No playable source');
  }

  static Map<String, String> _headers(String apiKey) => {
    'Authorization':
        'MediaBrowser Token="$apiKey", Client="Sakuga", Device="Sakuga", DeviceId="sakuga", Version="0.1.0"',
  };

  Future<List<JellyfinUser>> users() async {
    if (server.apiKey.isEmpty) {
      throw const AppException(FailureKind.auth);
    }
    final response = await _dio.get<List<dynamic>>('/Users');
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(JellyfinUser.fromJson)
        .where((user) => user.id.isNotEmpty)
        .toList();
  }

  Future<List<JellyfinView>> views(String userId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/UserViews',
        queryParameters: {'userId': userId},
      );
      return _parseViews(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final response = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Views',
      );
      return _parseViews(response.data);
    }
  }

  /// One page of a library view.
  ///
  /// [includeItemTypes] decides what the page contains: TV libraries should ask
  /// for `Series` only, so that episodes are not flattened into the poster grid.
  Future<JellyfinItemsPage> items(
    String userId,
    String parentId, {
    int startIndex = 0,
    int limit = 60,
    String includeItemTypes = 'Movie,Series,Episode,Video,MusicVideo',
    String sortBy = 'SortName',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Items',
      queryParameters: {
        'userId': userId,
        'parentId': parentId,
        'recursive': true,
        'includeItemTypes': includeItemTypes,
        'sortBy': sortBy,
        'sortOrder': 'Ascending',
        'fields': _itemFields,
        'imageTypeLimit': 1,
        'startIndex': startIndex,
        'limit': limit,
      },
    );
    return _parseItemsPage(response.data);
  }

  /// Seasons of a series, ordered by season number.
  Future<List<JellyfinItem>> seasons(String userId, String seriesId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Shows/$seriesId/Seasons',
      queryParameters: {
        'userId': userId,
        'fields': _itemFields,
        'imageTypeLimit': 1,
      },
    );
    final seasons = _parseItems(response.data);
    seasons.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
    return seasons;
  }

  /// Episodes of a series, optionally limited to one season.
  Future<List<JellyfinItem>> episodes(
    String userId,
    String seriesId, {
    String? seasonId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Shows/$seriesId/Episodes',
      queryParameters: {
        'userId': userId,
        'seasonId': ?seasonId,
        'fields': _itemFields,
        'imageTypeLimit': 1,
      },
    );
    final episodes = _parseItems(response.data);
    episodes.sort((a, b) {
      final season = (a.parentIndexNumber ?? 0).compareTo(
        b.parentIndexNumber ?? 0,
      );
      return season != 0
          ? season
          : (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
    });
    return episodes;
  }

  /// One item with the metadata the detail page renders.
  Future<JellyfinItem> item(String userId, String itemId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Items/$itemId',
      queryParameters: {
        'userId': userId,
        'fields':
            'Overview,Genres,People,Studios,ProviderIds,CommunityRating,'
            'OfficialRating,RunTimeTicks,PremiereDate,BackdropImageTags,'
            'Taglines,PrimaryImageAspectRatio,ImageTags,UserData',
      },
    );
    return JellyfinItem.fromJson(response.data ?? const {});
  }

  /// Items the user has started but not finished, most recent first.
  Future<List<JellyfinItem>> resume(String userId, {int limit = 12}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Items',
      queryParameters: {
        'userId': userId,
        'recursive': true,
        'filters': 'IsResumable',
        'includeItemTypes': 'Movie,Episode',
        'sortBy': 'DatePlayed',
        'sortOrder': 'Descending',
        'fields': _itemFields,
        'imageTypeLimit': 1,
        'limit': limit,
      },
    );
    return _parseItems(response.data);
  }

  /// Recently added media. The server answers with a plain array here.
  Future<List<JellyfinItem>> latest(String userId, {int limit = 12}) async {
    final response = await _dio.get<List<dynamic>>(
      '/Users/$userId/Items/Latest',
      queryParameters: {
        'limit': limit,
        'fields': _itemFields,
        'imageTypeLimit': 1,
      },
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  /// Server-side search across movies, series and videos.
  Future<List<JellyfinItem>> search(
    String userId,
    String term, {
    int limit = 60,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Items',
      queryParameters: {
        'userId': userId,
        'recursive': true,
        'searchTerm': term,
        'includeItemTypes': 'Movie,Series,Video',
        'sortBy': 'SortName',
        'sortOrder': 'Ascending',
        'fields': _itemFields,
        'imageTypeLimit': 1,
        'limit': limit,
      },
    );
    return _parseItems(response.data);
  }

  List<JellyfinView> _parseViews(Map<String, dynamic>? data) {
    final items = data?['Items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(JellyfinView.fromJson)
        .where((view) => view.id.isNotEmpty)
        .toList();
  }

  List<JellyfinItem> _parseItems(Map<String, dynamic>? data) {
    final items = data?['Items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  JellyfinItemsPage _parseItemsPage(Map<String, dynamic>? data) {
    final items = _parseItems(data);
    final total = (data?['TotalRecordCount'] as num?)?.toInt() ?? 0;
    return JellyfinItemsPage(
      items: items,
      totalRecordCount: total < items.length ? items.length : total,
    );
  }

  /// The scraped primary image for [item].
  ///
  /// Episodes rarely have a primary image of their own; the server then exposes
  /// the owning season/series image through `ParentPrimaryImageTag` or
  /// `SeriesPrimaryImageTag`, which is used as a fallback here.
  String? imageUrl(JellyfinItem item, {int width = 400}) {
    final primary = item.imageTags['Primary'];
    if (primary != null && primary.isNotEmpty) {
      return _imageUrl(item.id, primary, width);
    }
    final parentId = item.parentPrimaryImageItemId;
    final parentTag = item.parentPrimaryImageTag;
    if (parentId != null &&
        parentId.isNotEmpty &&
        parentTag != null &&
        parentTag.isNotEmpty) {
      return _imageUrl(parentId, parentTag, width);
    }
    final seriesId = item.seriesId;
    final seriesTag = item.seriesPrimaryImageTag;
    if (seriesId != null &&
        seriesId.isNotEmpty &&
        seriesTag != null &&
        seriesTag.isNotEmpty) {
      return _imageUrl(seriesId, seriesTag, width);
    }
    return null;
  }

  /// The first scraped backdrop, when the item has one.
  String? backdropUrl(JellyfinItem item, {int width = 1600}) {
    if (item.backdropImageTags.isEmpty) return null;
    final tag = item.backdropImageTags.first;
    if (tag.isEmpty) return null;
    return '${server.baseUrl}/Items/${item.id}/Images/Backdrop/0'
        '?maxWidth=$width&tag=$tag';
  }

  String _imageUrl(String itemId, String tag, int width) =>
      '${server.baseUrl}/Items/$itemId/Images/Primary?maxWidth=$width&tag=$tag';

  String _url(String path, {Map<String, String>? queryParameters}) =>
      Uri.parse('${server.baseUrl.replaceFirst(RegExp(r'/$'), '')}$path')
          .replace(queryParameters: queryParameters)
          .toString();

  String _absoluteUrl(String path) {
    final uri = Uri.parse(path);
    if (uri.hasScheme) return path;
    return '${server.baseUrl.replaceFirst(RegExp(r'/$'), '')}'
        '${path.startsWith('/') ? path : '/$path'}';
  }

  static Map<String, dynamic>? _preferredSource(
    List<Map<String, dynamic>> sources,
  ) {
    for (final source in sources) {
      if (source['SupportsDirectPlay'] == true) return source;
    }
    for (final source in sources) {
      final url = source['TranscodingUrl'];
      if (url is String && url.isNotEmpty) return source;
    }
    for (final source in sources) {
      if (source['SupportsDirectStream'] == true) return source;
    }
    return null;
  }

  static Duration _durationFromTicks(int ticks) =>
      Duration(microseconds: ticks ~/ 10);

  List<JellyfinSubtitleSource> _subtitleSources(Map<String, dynamic> source) =>
      (source['MediaStreams'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((stream) => stream['Type'] == 'Subtitle')
          .map((stream) {
            final deliveryUrl = stream['DeliveryUrl'] as String?;
            if (deliveryUrl == null || deliveryUrl.isEmpty) return null;
            return JellyfinSubtitleSource(
              url: _absoluteUrl(deliveryUrl),
              title: (stream['DisplayTitle'] ?? stream['Title']) as String?,
              language: stream['Language'] as String?,
            );
          })
          .whereType<JellyfinSubtitleSource>()
          .toList();

  static const _mpvDeviceProfile = <String, dynamic>{
    'Name': 'Sakuga-mpv',
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 120000000,
    'DirectPlayProfiles': [
      {
        'Container': 'mkv,webm,mp4,m4v,mov,ts,m2ts,avi,flv,3gp',
        'Type': 'Video',
        'VideoCodec': 'h264,hevc,av1,vp9,vp8,mpeg2video,mpeg4,vc1,msmpeg4',
        'AudioCodec': 'aac,ac3,eac3,dts,flac,opus,vorbis,mp3,alac,pcm',
      },
    ],
    'TranscodingProfiles': [
      {
        'Container': 'ts',
        'Type': 'Video',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,ac3,eac3',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'MinSegments': 1,
        'BreakOnNonKeyFrames': true,
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'ssa', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'pgssub', 'Method': 'External'},
      {'Format': 'dvdsub', 'Method': 'External'},
    ],
  };
}

class JellyfinPlaybackSource {
  const JellyfinPlaybackSource({
    required this.url,
    required this.headers,
    this.startPosition = Duration.zero,
    this.subtitles = const [],
  });

  final String url;
  final Map<String, String> headers;
  final Duration startPosition;
  final List<JellyfinSubtitleSource> subtitles;
}

class JellyfinSubtitleSource {
  const JellyfinSubtitleSource({required this.url, this.title, this.language});

  final String url;
  final String? title;
  final String? language;
}
