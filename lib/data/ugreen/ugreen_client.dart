import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import '../media_browser/media_browser_mapper.dart';
import '../media_server/media_models.dart';
import '../media_server/media_server_client.dart';
import '../media_server/playback_models.dart';
import '../media_server/server_profile.dart';
import 'ugreen_auth.dart';
import 'ugreen_playback_proxy.dart';
import 'ugreen_transport.dart';

const _itemFields =
    'RunTimeTicks,PrimaryImageAspectRatio,ImageTags,UserData,ChildCount,RecursiveItemCount';
const _defaultTypes = {
  MediaType.movie,
  MediaType.series,
  MediaType.episode,
  MediaType.video,
  MediaType.musicVideo,
};

class UgreenClient implements MediaServerClient {
  UgreenClient({required this.server, Dio? dio}) : _injectedDio = dio;

  @override
  final ServerProfile server;
  final Dio? _injectedDio;
  late final _baseUrl = normalizeUgreenBaseUrl(server.baseUrl);
  late final _apiBaseUrl = ugreenApiBaseUrl(_baseUrl);
  late final _fingerprint = normalizeUgreenFingerprint(
    server.certificateFingerprint,
  );
  late final _dio = _injectedDio ?? createUgreenDio(_baseUrl, _fingerprint);
  late final _mapper = MediaBrowserMapper(
    baseUrl: _apiBaseUrl,
    // UGOS exposes only the unindexed route for the primary backdrop.
    backdropKind: 'Backdrop',
    headers: ugreenArtworkHeaders(
      baseUrl: _baseUrl,
      fingerprint: _fingerprint,
      profileId: server.id,
      token: server.accessToken,
    ),
  );

  List<MediaLibrary>? _validatedViews;
  final _genreIdsByLibrary = <String, Map<String, String>>{};
  // The series page already loads every episode to build its season cards.
  ({String seriesId, List<MediaItem> episodes, DateTime loadedAt})?
  _seasonSnapshot;
  String get _deviceId => server.deviceId.isEmpty ? 'sakuga' : server.deviceId;
  String get _userPath => '/Users/${_pathId(server.userId)}';

  @override
  bool get isConfigured =>
      server.baseUrl.isNotEmpty &&
      server.accessToken.isNotEmpty &&
      server.userId.isNotEmpty;

  void _check(String userId) {
    if (!isConfigured || userId != server.userId) {
      throw const AppException(FailureKind.auth);
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, Object> query = const {},
    Map<String, Object>? payload,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        '$_apiBaseUrl$path',
        queryParameters: {...query, 'api_key': server.accessToken},
        data: payload,
        options: ugreenJsonOptions(
          deviceId: _deviceId,
          token: server.accessToken,
        )..method = payload == null ? 'GET' : 'POST',
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const AppException(FailureKind.invalidData);
      }
      return data;
    } on DioException catch (error) {
      throw ugreenRequestFailure(error);
    }
  }

  static List<dynamic> _rows(Map<String, dynamic> data) {
    final items = data['Items'];
    if (items is! List) throw const AppException(FailureKind.invalidData);
    return items;
  }

  static Map<String, dynamic> _normalizeIds(Map<String, dynamic> row) => {
    ...row,
    for (final key in const [
      'Id',
      'SeriesId',
      'SeasonId',
      'ParentPrimaryImageItemId',
      'ParentLogoItemId',
    ])
      key: ugreenId(row[key]),
  };

  List<MediaItem> _parseItems(
    List<dynamic> rows, {
    String? seriesId,
    int? season,
  }) {
    try {
      return [
        for (final row in rows.whereType<Map<String, dynamic>>())
          if (ugreenId(row['Id']) != null)
            _mapper.item(_itemRow(row, seriesId: seriesId, season: season)),
      ];
    } on TypeError {
      throw const AppException(FailureKind.invalidData);
    }
  }

  static Map<String, dynamic> _itemRow(
    Map<String, dynamic> row, {
    String? seriesId,
    int? season,
  }) {
    final data = _normalizeIds(row);
    // UGOS can advertise the Primary tag and its owner as top-level fields.
    final tags = Map<Object?, Object?>.of(
      row['ImageTags'] is Map ? row['ImageTags'] as Map : const {},
    );
    final primary =
        ugreenId(row['PrimaryImageTag']) ?? ugreenId(tags['Primary']);
    final owner = ugreenId(row['PrimaryImageItemId']);
    if (primary != null) {
      if (owner != null && owner != data['Id']) {
        tags.remove('Primary');
        data['ParentPrimaryImageItemId'] = owner;
        data['ParentPrimaryImageTag'] = primary;
      } else {
        tags['Primary'] = primary;
      }
      data['ImageTags'] = tags;
    }
    if (seriesId != null) data['Type'] = 'Episode';
    if (data['Type'] == 'Episode') {
      final series = seriesId ?? data['SeriesId'] as String?;
      final number = (data['ParentIndexNumber'] as num?)?.toInt() ?? season;
      data['SeriesId'] = series;
      data['ParentIndexNumber'] = number;
      data['SeasonId'] = series != null && number != null && number >= 0
          ? _seasonId(series, number)
          : null;
    }
    return data;
  }

  Future<List<MediaLibrary>> _fetchViews() async {
    final rows = _rows(await _request('$_userPath/Views'));
    try {
      final values = [
        for (final row in rows.whereType<Map<String, dynamic>>())
          if (ugreenId(row['Id']) != null) _mapper.library(_normalizeIds(row)),
      ];
      if (rows.isNotEmpty && values.isEmpty) {
        throw const AppException(FailureKind.invalidData);
      }
      return values;
    } on TypeError {
      throw const AppException(FailureKind.invalidData);
    }
  }

  @override
  Future<List<MediaUser>> users() async {
    _check(server.userId);
    _validatedViews = await _fetchViews();
    return [MediaUser(id: server.userId, name: server.username)];
  }

  @override
  Future<List<MediaLibrary>> views(String userId) async {
    _check(userId);
    final validated = _validatedViews;
    _validatedViews = null;
    return validated ?? _fetchViews();
  }

  @override
  Future<List<String>> genres(String userId, String parentId) async {
    _check(userId);
    final ids = await _fetchGenreIds(parentId);
    return ids.keys.toList();
  }

  Future<Map<String, String>> _fetchGenreIds(String parentId) async {
    final data = await _request(
      '/Genres',
      query: {
        'UserId': server.userId,
        'ParentId': parentId,
        'Recursive': true,
        'IncludeItemTypes': _defaultTypes
            .map(MediaBrowserMapper.itemType)
            .join(','),
      },
    );
    final ids = <String, String>{};
    for (final row in _rows(data).whereType<Map<String, dynamic>>()) {
      final name = row['Name'];
      final id = ugreenId(row['Id']);
      if (name is String && name.trim().isNotEmpty && id != null) {
        ids.putIfAbsent(name, () => id);
      }
    }
    return _genreIdsByLibrary[parentId] = ids;
  }

  @override
  Future<List<int>> years(String userId, String parentId) async => const [];

  @override
  Future<MediaItemsPage> items(
    String userId,
    String parentId, {
    int startIndex = 0,
    int limit = 60,
    Set<MediaType> types = _defaultTypes,
    MediaSort sort = MediaSort.name,
    String? genre,
    bool? isPlayed,
    int? year,
    bool descending = false,
  }) async {
    _check(userId);
    if (parentId.isEmpty || startIndex < 0) {
      throw const AppException(FailureKind.invalidData);
    }
    const empty = MediaItemsPage(
      items: [],
      totalRecordCount: 0,
      hasMore: false,
    );
    if (limit <= 0 || types.isEmpty) return empty;
    String? genreId;
    if (genre != null && genre.isNotEmpty) {
      // UGOS may silently ignore an unknown GenreIds value. Resolve against
      // fresh library options on the first page, then reuse them for paging.
      final ids = startIndex == 0
          ? await _fetchGenreIds(parentId)
          : _genreIdsByLibrary[parentId] ?? await _fetchGenreIds(parentId);
      genreId = ids[genre];
      if (genreId == null) return empty;
    }
    final data = await _request(
      '$_userPath/Items',
      query: {
        'ParentId': parentId,
        'GenreIds': ?genreId,
        'Recursive': true,
        'IncludeItemTypes': types.map(MediaBrowserMapper.itemType).join(','),
        'StartIndex': startIndex,
        'Limit': limit,
        'SortBy': 'SortName',
        'SortOrder': descending ? 'Descending' : 'Ascending',
        'Fields': _itemFields,
      },
    );
    final rows = _rows(data);
    final values = _parseItems(rows);
    final count = data['TotalRecordCount'];
    final reported = count is num ? count.toInt() : null;
    final next = startIndex + rows.length;
    final total = reported != null && reported >= next ? reported : null;
    final hasMore =
        rows.isNotEmpty &&
        (total == null ? rows.length >= limit : next < total);
    return MediaItemsPage(
      items: values,
      totalRecordCount: total,
      hasMore: hasMore,
      nextStartIndex: hasMore ? next : null,
    );
  }

  @override
  Future<MediaItem> item(String userId, String itemId) async {
    _check(userId);
    final season = _parseSeasonId(itemId);
    if (season != null) {
      final values = await episodes(userId, season.seriesId, seasonId: itemId);
      if (values.isEmpty) throw const AppException(FailureKind.invalidData);
      MediaItem? parent;
      try {
        // A direct link has no season card to provide the parent artwork.
        parent = await _serverItem(season.seriesId);
      } on AppException {
        // The episode list is still usable if the parent metadata is unavailable.
      }
      return _season(season.seriesId, season.number, values, parent: parent);
    }
    return _serverItem(itemId);
  }

  Future<MediaItem> _serverItem(String itemId) async {
    final data = await _request('$_userPath/Items/${_pathId(itemId)}');
    if (ugreenId(data['Id']) != itemId) {
      throw const AppException(FailureKind.invalidData);
    }
    return _parseItems([data]).single;
  }

  @override
  Future<List<MediaItem>> search(
    String userId,
    String term, {
    int limit = 60,
  }) async {
    _check(userId);
    final name = term.trim();
    if (name.isEmpty || limit <= 0) return const [];
    final data = await _request(
      '$_userPath/Items',
      query: {
        'SearchTerm': name,
        'Recursive': true,
        'IncludeItemTypes': 'Movie,Series,Video',
        'Limit': limit,
        'Fields': _itemFields,
      },
    );
    return _parseItems(_rows(data)).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> seasons(String userId, String seriesId) async {
    final grouped = <int, List<MediaItem>>{};
    final values = await episodes(userId, seriesId);
    _seasonSnapshot = (
      seriesId: seriesId,
      episodes: values,
      loadedAt: DateTime.now(),
    );
    for (final episode in values) {
      final season = episode.parentIndexNumber;
      if (season != null && season >= 0) {
        grouped.putIfAbsent(season, () => []).add(episode);
      }
    }
    return [
      for (final number in grouped.keys.toList()..sort())
        _season(seriesId, number, grouped[number]!),
    ];
  }

  static MediaItem _season(
    String seriesId,
    int number,
    List<MediaItem> episodes, {
    MediaItem? parent,
  }) => MediaItem(
    id: _seasonId(seriesId, number),
    name: 'Season $number',
    type: MediaType.season,
    poster: parent?.poster ?? episodes.first.seriesPoster,
    backdrop: parent?.backdrop,
    seriesId: seriesId,
    seriesName: episodes.first.seriesName ?? parent?.name,
    indexNumber: number,
    childCount: episodes.length,
  );

  // Season cards link to item(); keep the parent series in the route-safe ID.
  static String _seasonId(String seriesId, int number) =>
      'ugreen-season:${base64Url.encode(utf8.encode(seriesId)).replaceAll('=', '')}:$number';

  static ({String seriesId, int number})? _parseSeasonId(String id) {
    final parts = id.split(':');
    if (parts.length != 3 || parts.first != 'ugreen-season') return null;
    final number = int.tryParse(parts[2]);
    if (number == null || number < 0) return null;
    try {
      final seriesId = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return seriesId.isEmpty ? null : (seriesId: seriesId, number: number);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<List<MediaItem>> episodes(
    String userId,
    String seriesId, {
    String? seasonId,
  }) async {
    _check(userId);
    final parsed = seasonId == null ? null : _parseSeasonId(seasonId);
    final season =
        parsed?.number ?? (seasonId == null ? null : int.tryParse(seasonId));
    if (seasonId != null &&
        (season == null ||
            season < 0 ||
            (parsed != null && parsed.seriesId != seriesId))) {
      throw const AppException(FailureKind.invalidData);
    }
    final snapshot = _seasonSnapshot;
    if (season != null &&
        snapshot != null &&
        snapshot.seriesId == seriesId &&
        DateTime.now().difference(snapshot.loadedAt) <
            const Duration(minutes: 2)) {
      final cached = snapshot.episodes
          .where((item) => item.parentIndexNumber == season)
          .toList();
      if (cached.isNotEmpty) return cached;
    }
    final data = await _request(
      '/Shows/${_pathId(seriesId)}/Episodes',
      query: {'IsMissing': false, 'Season': ?season},
    );
    return _parseItems(_rows(data), seriesId: seriesId, season: season)
      ..removeWhere(
        (item) => season != null && item.parentIndexNumber != season,
      )
      ..sort((a, b) {
        final order = (a.parentIndexNumber ?? 0).compareTo(
          b.parentIndexNumber ?? 0,
        );
        return order != 0
            ? order
            : (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0);
      });
  }

  @override
  Future<List<MediaItem>> resume(String userId, {int limit = 12}) async {
    _check(userId);
    if (limit <= 0) return const [];
    final data = await _request(
      '$_userPath/Items/Resume',
      query: {
        'Limit': limit,
        'MediaTypes': 'Video',
        'SortBy': 'DatePlayed',
        'SortOrder': 'Descending',
      },
    );
    return _parseItems(_rows(data)).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> latest(String userId, {int limit = 12}) async {
    _check(userId);
    if (limit <= 0) return const [];
    final data = await _request(
      '$_userPath/Items',
      query: {
        'Recursive': true,
        'IncludeItemTypes': 'Movie,Series',
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
        'Limit': limit,
        'Fields': _itemFields,
      },
    );
    return _parseItems(_rows(data)).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> randomItems(String userId, {int limit = 8}) async {
    _check(userId);
    if (limit <= 0) return const [];
    // UGOS can ignore Random sorting. Sample a bounded pool locally instead
    // of paging through the entire library on a home-page refresh.
    const candidateLimit = 60;
    final data = await _request(
      '$_userPath/Items',
      query: {
        'Recursive': true,
        'IncludeItemTypes': 'Movie,Series',
        'Limit': candidateLimit,
        'Fields': _itemFields,
      },
    );
    final candidates = _parseItems(_rows(data).take(candidateLimit).toList());
    final seen = <String>{};
    final withBackdrop = <MediaItem>[];
    final withPosterOnly = <MediaItem>[];
    for (final item in candidates) {
      if (item.type != MediaType.movie && item.type != MediaType.series) {
        continue;
      }
      if (item.backdrop == null && item.poster == null) continue;
      if (!seen.add(item.id)) continue;
      (item.backdrop != null ? withBackdrop : withPosterOnly).add(item);
    }
    final random = Random();
    withBackdrop.shuffle(random);
    withPosterOnly.shuffle(random);
    return withBackdrop.followedBy(withPosterOnly).take(limit).toList();
  }

  @override
  Future<PlaybackSource> playbackSource(
    String userId,
    String itemId, {
    Duration? startPosition,
    int? maxStreamingBitrate,
    int? maxVideoHeight,
  }) async {
    _check(userId);
    final data = await _request(
      '/Items/${_pathId(itemId)}/PlaybackInfo',
      payload: {
        'UserId': userId,
        'IsPlayback': false,
        'EnableDirectPlay': true,
        'EnableDirectStream': true,
        'EnableTranscoding': false,
      },
    );
    final errorCode = data['ErrorCode'];
    if (errorCode is String && errorCode.isNotEmpty) {
      throw const AppException(FailureKind.server);
    }
    final sources = data['MediaSources'];
    if (sources is List) {
      for (final source in sources.whereType<Map<String, dynamic>>()) {
        if (source['RequiresOpening'] == true ||
            source['RequiresClosing'] == true ||
            source['IsInfiniteStream'] == true ||
            source['Type'] == 'Live' ||
            source['LiveStreamId'] != null) {
          continue;
        }
        final link = source['DirectStreamUrl'];
        if (link is! String || link == source['TranscodingUrl']) continue;
        final upstream = _upstream(link);
        if (upstream == null) continue;
        final proxy = await UgreenPlaybackProxy.start(
          baseUrl: _baseUrl,
          fingerprint: _fingerprint,
          upstream: upstream,
        );
        return PlaybackSource(
          url: proxy.url,
          headers: const {},
          session: _UgreenPlaybackSession(this, proxy),
          startPosition: startPosition ?? Duration.zero,
          playMethod: PlayMethod.directPlay,
        );
      }
    }
    throw const AppException(
      FailureKind.invalidData,
      'No same-origin original stream',
    );
  }

  Uri? _upstream(String link) {
    if (link.isEmpty || link.contains(RegExp(r'[\x00-\x20\x7f\\]'))) {
      return null;
    }
    final target = Uri.tryParse(link);
    if (target == null || target.path.isEmpty || target.hasFragment) {
      return null;
    }
    final base = Uri.parse('$_apiBaseUrl/');
    final prefixed =
        !target.hasScheme &&
        !target.hasAuthority &&
        target.path.toLowerCase().startsWith('emby/');
    final url = (prefixed ? Uri.parse(base.origin) : base).resolveUri(target);
    try {
      requireUgreenOrigin(base, url);
    } on FormatException {
      return null;
    }
    final path = url.path.toLowerCase();
    if (path.endsWith('.m3u8') || path.endsWith('.mpd')) return null;
    // Keep the supplied query, including duplicate parameters. Inspect only
    // names: opaque signed parameter values need not contain valid UTF-8.
    if (url.query.split('&').any((part) {
      try {
        final name = Uri.decodeQueryComponent(part.split('=').first);
        return name.toLowerCase() == 'api_key';
      } on FormatException {
        return false;
      }
    })) {
      return url;
    }
    final auth = 'api_key=${Uri.encodeQueryComponent(server.accessToken)}';
    return url.replace(query: url.query.isEmpty ? auth : '${url.query}&$auth');
  }

  static String _pathId(String id) {
    if (id.isEmpty || id == '.' || id == '..') {
      throw const AppException(FailureKind.invalidData);
    }
    return Uri.encodeComponent(id);
  }

  @override
  Future<void> stopTranscoding(PlaybackSession session) async {
    if (session is _UgreenPlaybackSession && identical(session.client, this)) {
      await session.proxy.close();
    }
  }

  // Ugreen progress is stored locally, never sent to unverified endpoints.
  @override
  Future<void> reportPlaybackStarted(
    PlaybackSession session, {
    required Duration position,
    required bool isPaused,
    double volume = 100,
  }) async {}

  @override
  Future<void> reportPlaybackProgress(
    PlaybackSession session, {
    required Duration position,
    required bool isPaused,
    double volume = 100,
  }) async {}

  @override
  Future<void> reportPlaybackStopped(
    PlaybackSession session, {
    required Duration position,
    required bool failed,
    double volume = 100,
  }) async {}

  @override
  Future<void> updatePlaybackPosition(
    String userId,
    String itemId, {
    required Duration position,
    bool? played,
    PlaybackSession? session,
  }) async {}

  @override
  Future<void> setPlayed(
    String userId,
    String itemId, {
    required bool played,
  }) async => throw UnsupportedError(
    'Remote watched status is not supported by Ugreen',
  );
}

class _UgreenPlaybackSession implements PlaybackSession {
  const _UgreenPlaybackSession(this.client, this.proxy);
  final UgreenClient client;
  final UgreenPlaybackProxy proxy;
}
