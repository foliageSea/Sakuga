import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import '../media_server/media_models.dart';
import '../media_server/media_server_client.dart';
import '../media_server/playback_models.dart';
import '../media_server/server_profile.dart';
import 'media_browser_mapper.dart';
import 'media_browser_playback_session.dart';

abstract class MediaBrowserClient implements MediaServerClient {
  static const _playbackReportTimeout = Duration(seconds: 3);

  MediaBrowserClient({
    required this.server,
    Dio? dio,
    required Map<String, String> headers,
    this.emby = false,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: server.baseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 10),
               headers: headers,
             ),
           );

  @override
  final ServerProfile server;

  @override
  bool get isConfigured;
  final bool emby;
  final Dio _dio;

  late final _mapper = MediaBrowserMapper(
    baseUrl: apiBaseUrl,
    headers: authHeaders,
  );

  /// Fields shared by every browse request: scraped image metadata plus the
  /// per-user playback state.
  static const _itemFields =
      'RunTimeTicks,PrimaryImageAspectRatio,ImageTags,UserData,ChildCount,RecursiveItemCount,Overview';
  static const _itemImageTypes = 'Primary,Backdrop,Logo';

  Map<String, String> get authHeaders;

  MediaBrowserPlaybackSession createSession({
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required PlayMethod playMethod,
  });

  String get apiBaseUrl => server.baseUrl;

  /// Device identity sent in authorization; transcoding jobs are keyed by it.
  String get playbackDeviceId;

  String absoluteUrl(String path) {
    final uri = Uri.parse(path);
    if (uri.hasScheme) return path;
    return '${apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}${path.startsWith('/') ? path : '/$path'}';
  }

  Map<String, String> playbackHeaders(
    String url,
    Map<String, String> headers,
  ) => headers;
  String subtitleUrl(String path) => absoluteUrl(path);
  String? externalSubtitlePath(
    Map<String, dynamic> stream,
    Map<String, dynamic> source,
    String itemId,
  ) => stream['DeliveryUrl'] as String?;
  bool acceptsSession(MediaBrowserPlaybackSession session) => true;

  /// Negotiates a playable stream for [itemId].
  ///
  /// mpv supports the common Jellyfin containers and codecs directly. The
  /// server can still return a transcoding URL when the source is not suitable
  /// for direct playback; that URL must be used as-is.
  @override
  Future<PlaybackSource> playbackSource(
    String userId,
    String itemId, {
    Duration? startPosition,
    int? maxStreamingBitrate,
    int? maxVideoHeight,
  }) async {
    startPosition ??= Duration.zero;
    final startTimeTicks = mediaBrowserTicks(startPosition);
    final bitrate = maxStreamingBitrate ?? defaultMaxStreamingBitrate;
    final response = await _dio.post<Map<String, dynamic>>(
      '/Items/$itemId/PlaybackInfo',
      queryParameters: {'userId': userId},
      data: {
        'UserId': userId,
        if (emby) 'IsPlayback': true,
        'StartTimeTicks': startTimeTicks,
        // Servers fall back to transcoding when the source exceeds this limit.
        'MaxStreamingBitrate': bitrate,
        'EnableDirectPlay': true,
        'EnableDirectStream': true,
        'EnableTranscoding': true,
        'AllowVideoStreamCopy': true,
        'AllowAudioStreamCopy': true,
        'DeviceProfile': {
          ..._mpvDeviceProfile,
          'MaxStreamingBitrate': bitrate,
          'MaxStaticBitrate': bitrate,
          // Servers reject direct play above this height and scale the
          // transcode down to it (TranscodingUrl carries MaxHeight).
          if (maxVideoHeight != null)
            'CodecProfiles': [
              {
                'Type': 'Video',
                'Conditions': [
                  {
                    'Condition': 'LessThanEqual',
                    'Property': 'Height',
                    'Value': '$maxVideoHeight',
                    'IsRequired': false,
                  },
                ],
              },
            ],
        },
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
    final eligibleSources = emby
        ? sources
              .where(
                (source) =>
                    source['RequiresOpening'] != true &&
                    source['RequiresClosing'] != true &&
                    source['LiveStreamId'] == null &&
                    source['IsInfiniteStream'] != true &&
                    source['Type'] != 'Live',
              )
              .toList()
        : sources;
    final source = _preferredSource(eligibleSources);
    if (source == null) {
      if (emby && sources.isNotEmpty && eligibleSources.isEmpty) {
        throw const AppException(
          FailureKind.invalidData,
          'Live streams and sources requiring opening are not supported',
        );
      }
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
    final subtitles = _subtitleSources(source, itemId);
    final playMethod = source['SupportsDirectPlay'] == true
        ? PlayMethod.directPlay
        : (source['TranscodingUrl'] as String?)?.isNotEmpty == true
        ? PlayMethod.transcode
        : PlayMethod.directStream;
    final session = createSession(
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      playSessionId: playSessionId,
      playMethod: playMethod,
    );

    if (source['SupportsDirectPlay'] == true) {
      return PlaybackSource(
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
        session: session,
        playMethod: playMethod,
      );
    }

    final transcodingUrl = source['TranscodingUrl'] as String?;
    if (transcodingUrl != null && transcodingUrl.isNotEmpty) {
      final isHls =
          source['TranscodingSubProtocol']?.toString().toLowerCase() == 'hls';
      final transcodeOffset =
          isHls || _queryFlag(transcodingUrl, 'CopyTimestamps')
          ? Duration.zero
          : _durationFromTicks(startTimeTicks);
      return PlaybackSource(
        url: absoluteUrl(transcodingUrl),
        headers: playbackHeaders(absoluteUrl(transcodingUrl), headers),
        startPosition: isHls
            ? _durationFromTicks(startTimeTicks)
            : Duration.zero,
        initialPosition: _durationFromTicks(startTimeTicks),
        positionOffset: transcodeOffset,
        subtitles: subtitles,
        session: session,
        playMethod: playMethod,
      );
    }

    if (source['SupportsDirectStream'] == true) {
      return PlaybackSource(
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
        session: session,
        playMethod: playMethod,
      );
    }

    throw const AppException(FailureKind.invalidData, 'No playable source');
  }

  @override
  Future<void> stopTranscoding(PlaybackSession session) async {
    if (session is! MediaBrowserPlaybackSession ||
        !acceptsSession(session) ||
        session.playMethod != PlayMethod.transcode ||
        session.playSessionId.isEmpty) {
      return;
    }
    final cancelToken = CancelToken();
    try {
      await _dio
          .delete<void>(
            '/Videos/ActiveEncodings',
            queryParameters: {
              'deviceId': playbackDeviceId,
              'playSessionId': session.playSessionId,
            },
            cancelToken: cancelToken,
            options: Options(
              connectTimeout: _playbackReportTimeout,
              sendTimeout: _playbackReportTimeout,
              receiveTimeout: _playbackReportTimeout,
            ),
          )
          .timeout(_playbackReportTimeout);
    } on TimeoutException {
      cancelToken.cancel('Transcoding cleanup timed out');
      rethrow;
    }
  }

  @override
  Future<void> reportPlaybackStarted(
    PlaybackSession session, {
    required Duration position,
    required bool isPaused,
    double volume = 100,
  }) => _reportPlayback(
    '/Sessions/Playing',
    session,
    positionTicks: mediaBrowserTicks(position),
    isPaused: isPaused,
    volume: volume,
  );

  @override
  Future<void> reportPlaybackProgress(
    PlaybackSession session, {
    required Duration position,
    required bool isPaused,
    double volume = 100,
  }) => _reportPlayback(
    '/Sessions/Playing/Progress',
    session,
    positionTicks: mediaBrowserTicks(position),
    isPaused: isPaused,
    volume: volume,
  );

  @override
  Future<void> reportPlaybackStopped(
    PlaybackSession session, {
    required Duration position,
    required bool failed,
    double volume = 100,
  }) => _reportPlayback(
    '/Sessions/Playing/Stopped',
    session,
    positionTicks: mediaBrowserTicks(position),
    isPaused: true,
    volume: volume,
    failed: failed,
  );

  @override
  Future<void> setPlayed(
    String userId,
    String itemId, {
    required bool played,
  }) async {
    final path = '/Users/$userId/PlayedItems/$itemId';
    if (played) {
      await _dio.post<void>(path);
    } else {
      await _dio.delete<void>(path);
    }
  }

  /// Persists resume progress for an explicit user. Session playback reports
  /// cannot infer a user when the client authenticates with an API key.
  @override
  Future<void> updatePlaybackPosition(
    String userId,
    String itemId, {
    required Duration position,
    bool? played,
    PlaybackSession? session,
  }) async {
    final payload = {
      'PlaybackPositionTicks': mediaBrowserTicks(position),
      'LastPlayedDate': DateTime.now().toUtc().toIso8601String(),
      'Played': ?played,
    };
    try {
      if (emby) {
        await _postPlaybackUpdate(
          '/Users/$userId/Items/$itemId/UserData',
          data: payload,
        );
        return;
      }
      await _postPlaybackUpdate(
        '/UserItems/$itemId/UserData',
        queryParameters: {'userId': userId},
        data: payload,
      );
    } on DioException catch (error) {
      if (emby || error.response?.statusCode != 404) rethrow;
      await _postPlaybackUpdate(
        '/Users/$userId/Items/$itemId/UserData',
        data: payload,
      );
    }
  }

  Future<void> _postPlaybackUpdate(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? data,
  }) async {
    final cancelToken = CancelToken();
    try {
      await _dio
          .post<void>(
            path,
            queryParameters: queryParameters,
            data: data,
            cancelToken: cancelToken,
            options: Options(
              connectTimeout: _playbackReportTimeout,
              sendTimeout: _playbackReportTimeout,
              receiveTimeout: _playbackReportTimeout,
            ),
          )
          .timeout(_playbackReportTimeout);
    } on TimeoutException {
      cancelToken.cancel('Playback update timed out');
      rethrow;
    }
  }

  Future<void> _reportPlayback(
    String path,
    PlaybackSession session, {
    required int positionTicks,
    required bool isPaused,
    required double volume,
    bool? failed,
  }) async {
    if (session is! MediaBrowserPlaybackSession || !acceptsSession(session)) {
      throw ArgumentError.value(
        session,
        'session',
        'Expected a MediaBrowser session',
      );
    }
    await _postPlaybackUpdate(
      path,
      data: {
        'ItemId': session.itemId,
        if (session.mediaSourceId.isNotEmpty)
          'MediaSourceId': session.mediaSourceId,
        if (session.playSessionId.isNotEmpty)
          'PlaySessionId': session.playSessionId,
        'PositionTicks': positionTicks,
        'IsPaused': isPaused,
        'IsMuted': volume <= 0,
        'VolumeLevel': volume.round().clamp(0, 100),
        'CanSeek': true,
        'PlayMethod': switch (session.playMethod) {
          PlayMethod.directPlay => 'DirectPlay',
          PlayMethod.directStream => 'DirectStream',
          PlayMethod.transcode => 'Transcode',
        },
        'RepeatMode': 'RepeatNone',
        'Failed': ?failed,
      },
    );
  }

  @override
  Future<List<MediaUser>> users() async {
    if (!isConfigured) {
      throw const AppException(FailureKind.auth);
    }
    if (server.usesAccount) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/Users/${Uri.encodeComponent(server.userId)}',
      );
      final user = _mapper.user(response.data ?? const {});
      return user.id.isEmpty ? const [] : [user];
    }
    final response = await _dio.get<List<dynamic>>('/Users');
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_mapper.user)
        .where((user) => user.id.isNotEmpty)
        .toList();
  }

  @override
  Future<List<MediaLibrary>> views(String userId) async {
    if (emby) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Views',
      );
      return _parseViews(response.data);
    }
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

  @override
  Future<List<String>> genres(String userId, String parentId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Genres',
      queryParameters: {
        'UserId': userId,
        'ParentId': parentId,
        'Recursive': true,
        'IncludeItemTypes': 'Movie,Series,Episode,Video,MusicVideo',
      },
    );
    return (response.data?['Items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((item) => item['Name'])
        .whereType<String>()
        .toList();
  }

  @override
  Future<List<int>> years(String userId, String parentId) async {
    if (emby) {
      final response = await _dio.get<Map<String, dynamic>>(
        '/Years',
        queryParameters: {
          'userId': userId,
          'parentId': parentId,
          'recursive': true,
          'includeItemTypes': 'Movie,Series,Video,MusicVideo',
          'enableImages': false,
          'enableUserData': false,
          'sortBy': 'SortName',
          'sortOrder': 'Descending',
        },
      );
      return (response.data?['Items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => int.tryParse(item['Name']?.toString() ?? ''))
          .whereType<int>()
          .where((year) => year > 0)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/Items/Filters',
      queryParameters: {
        'userId': userId,
        'parentId': parentId,
        'includeItemTypes': 'Movie,Series,Video,MusicVideo',
      },
    );
    return (response.data?['Years'] as List? ?? const [])
        .whereType<int>()
        .where((year) => year > 0)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  /// One page of a library view.
  ///
  /// [types] decides what the page contains: TV libraries should ask
  /// for `Series` only, so that episodes are not flattened into the poster grid.
  @override
  Future<MediaItemsPage> items(
    String userId,
    String parentId, {
    int startIndex = 0,
    int limit = 60,
    Set<MediaType> types = const {
      MediaType.movie,
      MediaType.series,
      MediaType.episode,
      MediaType.video,
      MediaType.musicVideo,
    },
    MediaSort sort = MediaSort.name,
    String? genre,
    bool? isPlayed,
    int? year,
    bool descending = false,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      emby ? '/Users/$userId/Items' : '/Items',
      queryParameters: {
        'userId': userId,
        'parentId': parentId,
        'recursive': true,
        'includeItemTypes': types.map(MediaBrowserMapper.itemType).join(','),
        if (genre != null && genre.isNotEmpty) 'Genres': genre,
        'isPlayed': ?isPlayed,
        'years': ?year,
        'sortBy': switch (sort) {
          MediaSort.name => 'SortName',
          MediaSort.random => 'Random',
          MediaSort.dateAdded => 'DateCreated',
          MediaSort.year => 'ProductionYear',
          MediaSort.rating => 'CommunityRating',
        },
        'sortOrder': descending ? 'Descending' : 'Ascending',
        'fields': _itemFields,
        'enableImageTypes': _itemImageTypes,
        'imageTypeLimit': 1,
        'startIndex': startIndex,
        'limit': limit,
      },
    );
    return _parseItemsPage(response.data);
  }

  /// Seasons of a series, ordered by season number.
  @override
  Future<List<MediaItem>> seasons(String userId, String seriesId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Shows/$seriesId/Seasons',
      queryParameters: {
        'userId': userId,
        'fields': _itemFields,
        'enableImageTypes': _itemImageTypes,
        'imageTypeLimit': 1,
      },
    );
    final seasons = _parseItems(response.data);
    seasons.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
    return seasons;
  }

  /// Episodes of a series, optionally limited to one season.
  @override
  Future<List<MediaItem>> episodes(
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
        'enableImageTypes': _itemImageTypes,
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
  @override
  Future<MediaItem> item(String userId, String itemId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      emby ? '/Users/$userId/Items/$itemId' : '/Items/$itemId',
      queryParameters: {
        'userId': userId,
        'fields':
            'Overview,Genres,People,Studios,ProviderIds,CommunityRating,'
            'OfficialRating,RunTimeTicks,PremiereDate,BackdropImageTags,'
            'Taglines,PrimaryImageAspectRatio,ImageTags,UserData',
        'enableImageTypes': _itemImageTypes,
      },
    );
    return _mapper.item(response.data ?? const {});
  }

  /// Uses Jellyfin's default resume list and preserves its ordering.
  @override
  Future<List<MediaItem>> resume(String userId, {int limit = 12}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Users/$userId/Items/Resume',
      queryParameters: {
        'limit': limit,
        'fields': _itemFields,
        'enableImageTypes': _itemImageTypes,
        'imageTypeLimit': 1,
        'mediaTypes': 'Video',
      },
    );
    return _parseItems(response.data);
  }

  /// Recently added media. The server answers with a plain array here.
  @override
  Future<List<MediaItem>> latest(String userId, {int limit = 12}) async {
    final response = await _dio.get<List<dynamic>>(
      '/Users/$userId/Items/Latest',
      queryParameters: {
        'limit': limit,
        'fields': _itemFields,
        'enableImageTypes': _itemImageTypes,
        'imageTypeLimit': 1,
      },
    );
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_mapper.item)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  /// Random movies and series with hero metadata for the home carousel.
  @override
  Future<List<MediaItem>> randomItems(String userId, {int limit = 8}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      emby ? '/Users/$userId/Items' : '/Items',
      queryParameters: {
        'userId': userId,
        'recursive': true,
        'includeItemTypes': 'Movie,Series',
        'sortBy': 'Random',
        'fields':
            'Overview,Genres,OfficialRating,PremiereDate,'
            'BackdropImageTags,PrimaryImageAspectRatio,ImageTags,UserData,'
            'RunTimeTicks',
        'enableImageTypes': _itemImageTypes,
        'imageTypeLimit': 1,
        'limit': limit,
      },
    );
    return _parseItems(response.data);
  }

  /// Server-side search across movies, series and videos.
  @override
  Future<List<MediaItem>> search(
    String userId,
    String term, {
    int limit = 60,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      emby ? '/Users/$userId/Items' : '/Items',
      queryParameters: {
        'userId': userId,
        'recursive': true,
        'searchTerm': term,
        'includeItemTypes': 'Movie,Series,Video',
        'sortBy': 'SortName',
        'sortOrder': 'Ascending',
        'fields': _itemFields,
        'enableImageTypes': _itemImageTypes,
        'imageTypeLimit': 1,
        'limit': limit,
      },
    );
    return _parseItems(response.data);
  }

  List<MediaLibrary> _parseViews(Map<String, dynamic>? data) {
    final items = data?['Items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_mapper.library)
        .where((view) => view.id.isNotEmpty)
        .toList();
  }

  List<MediaItem> _parseItems(Map<String, dynamic>? data) {
    final items = data?['Items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_mapper.item)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  MediaItemsPage _parseItemsPage(Map<String, dynamic>? data) {
    final items = _parseItems(data);
    final total = (data?['TotalRecordCount'] as num?)?.toInt() ?? 0;
    return MediaItemsPage(
      items: items,
      totalRecordCount: total < items.length ? items.length : total,
    );
  }

  String _url(String path, {Map<String, String>? queryParameters}) =>
      Uri.parse(absoluteUrl(path))
          .replace(queryParameters: queryParameters)
          .toString();

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

  static bool _queryFlag(String url, String name) {
    final parameters = Uri.parse(url).queryParameters;
    for (final entry in parameters.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value.toLowerCase() == 'true';
      }
    }
    return false;
  }

  List<SubtitleSource> _subtitleSources(
    Map<String, dynamic> source,
    String itemId,
  ) => (source['MediaStreams'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .where(
        (stream) =>
            stream['Type'] == 'Subtitle' &&
            stream['SupportsExternalStream'] != false &&
            (stream['DeliveryMethod'] == null ||
                stream['DeliveryMethod'] == 'External'),
      )
      .map((stream) {
        final deliveryUrl = externalSubtitlePath(stream, source, itemId);
        if (deliveryUrl == null || deliveryUrl.isEmpty) {
          return null;
        }
        return SubtitleSource(
          url: subtitleUrl(deliveryUrl),
          title: (stream['DisplayTitle'] ?? stream['Title']) as String?,
          language: stream['Language'] as String?,
        );
      })
      .whereType<SubtitleSource>()
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
      // Keep bitmap subtitles in the video container for mpv to decode,
      // rather than requesting raw codec URLs such as Stream.dvdsub.
      {'Format': 'pgssub', 'Method': 'Embed'},
      {'Format': 'dvdsub', 'Method': 'Embed'},
    ],
  };
}
