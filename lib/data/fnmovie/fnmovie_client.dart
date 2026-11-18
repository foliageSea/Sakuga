import 'dart:math';

import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import '../media_server/media_models.dart';
import '../media_server/media_server_client.dart';
import '../media_server/playback_models.dart';
import '../media_server/server_profile.dart';
import 'fnmovie_api.dart';
import 'fnmovie_mapper.dart';
import 'fnmovie_playback_proxy.dart';
import 'fnmovie_protocol.dart';

const _rootTypes = {MediaType.movie, MediaType.series, MediaType.video};

class FnMovieClient implements MediaServerClient {
  FnMovieClient({required this.server, Dio? dio})
    : _api = FnMovieApi(server.baseUrl, token: server.accessToken, dio: dio);

  final FnMovieApi _api;
  late final _mapper = FnMovieMapper(_api.base, server.accessToken, server.id);
  final _knownItems = <String, MediaItem>{};
  final _pageSizes = <(String, int, String), int>{};
  List<MediaLibrary>? _initialViews;

  @override
  final ServerProfile server;

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

  @override
  Future<List<MediaUser>> users() async {
    _check(server.userId);
    _initialViews =
        await _fetchViews(); // Verify the token, not a public probe.
    return [MediaUser(id: server.userId, name: server.username)];
  }

  @override
  Future<List<MediaLibrary>> views(String userId) async {
    _check(userId);
    final initial = _initialViews;
    _initialViews = null;
    return initial ?? _fetchViews();
  }

  Future<List<MediaLibrary>> _fetchViews() async =>
      (await fetchFnMovieLibraries(_api))
          .map(_mapper.library)
          .nonNulls
          .toList();

  @override
  Future<List<String>> genres(String userId, String parentId) async => const [];

  @override
  Future<List<int>> years(String userId, String parentId) async => const [];

  @override
  Future<MediaItemsPage> items(
    String userId,
    String parentId, {
    int startIndex = 0,
    int limit = 60,
    Set<MediaType> types = _rootTypes,
    MediaSort sort = MediaSort.name,
    String? genre,
    bool? isPlayed,
    int? year,
    bool descending = false,
  }) async {
    _check(userId);
    if (parentId.isEmpty || limit <= 0) {
      throw const AppException(FailureKind.invalidData);
    }
    final pageSize = min(limit, 200);
    final page = max(0, startIndex) ~/ pageSize + 1;
    final requested = types.intersection(_rootTypes);
    if (requested.isEmpty) {
      return const MediaItemsPage(items: [], totalRecordCount: 0);
    }
    final tags = [
      if (requested.contains(MediaType.movie)) 'Movie',
      if (requested.contains(MediaType.series)) 'TV',
      if (requested.contains(MediaType.video)) 'Video',
    ];
    final data = await _api.post('item/list', {
      'ancestor_guid': parentId,
      'page': page,
      'page_size': pageSize,
      'tags': {'type': tags},
    });
    final rows = fnRows(data);
    final scoped = rows.any((row) => FnMovieMapper.libraryId(row) != null);
    final values = _parse(
      rows.where((row) => !scoped || FnMovieMapper.libraryId(row) == parentId),
    ).where((item) => requested.contains(item.type)).toList();
    final total = fnNumber(fnObject(data), const [
      'total',
      'total_count',
    ])?.toInt();
    final reportedPageSize = fnNumber(fnObject(data), const [
      'page_size',
      'pageSize',
    ])?.toInt();
    final pageKey = (parentId, pageSize, tags.join(','));
    if (page == 1) {
      _pageSizes.remove(pageKey);
      if (rows.isNotEmpty &&
          rows.length < pageSize &&
          total != null &&
          total > rows.length) {
        if (_pageSizes.length >= 64) _pageSizes.remove(_pageSizes.keys.first);
        _pageSizes[pageKey] = rows.length;
      }
    }
    final serverPageSize = reportedPageSize != null && reportedPageSize > 0
        ? reportedPageSize
        : _pageSizes[pageKey] ?? pageSize;
    final hasMore =
        rows.isNotEmpty &&
        (total != null && total > 0
            ? page * serverPageSize < total
            : rows.length >= serverPageSize);
    return MediaItemsPage(
      items: values,
      totalRecordCount: total != null && total >= values.length ? total : null,
      hasMore: hasMore,
      nextStartIndex: hasMore ? page * pageSize : null,
    );
  }

  List<MediaItem> _parse(
    Iterable<Map<String, dynamic>> rows, {
    MediaType? hint,
    String? seriesId,
    String? seasonId,
    int? seasonNumber,
  }) {
    final ids = <String>{};
    return [
      for (final row in rows)
        if (_mapper.item(
              row,
              hint: hint,
              seriesId: seriesId,
              seasonId: seasonId,
              seasonNumber: seasonNumber,
            )
            case final item?)
          if (item.type != MediaType.unknown && ids.add(item.id))
            _remember(item),
    ];
  }

  MediaItem _remember(MediaItem item) {
    _knownItems.remove(item.id);
    if (_knownItems.length >= 512) _knownItems.remove(_knownItems.keys.first);
    _knownItems[item.id] = item;
    return item;
  }

  @override
  Future<MediaItem> item(String userId, String itemId) async {
    _check(userId);
    final id = Uri.encodeComponent(itemId);
    final preview = _knownItems[itemId];
    final hint = preview?.type;
    Map<String, dynamic> row;
    try {
      row = _detail(await _api.get('item/$id'));
    } on AppException catch (error) {
      if (!_unavailable(error)) rethrow;
      final route = switch (hint) {
        MediaType.series => 'tv',
        MediaType.movie || MediaType.video => 'movie',
        _ => null,
      };
      if (route == null) {
        if (preview?.type == MediaType.episode) return preview!;
        rethrow;
      }
      row = _detail(await _api.get('$route/$id'));
    }
    if (row.isEmpty) throw const AppException(FailureKind.invalidData);
    var people = <MediaPerson>[];
    try {
      final data = await _api.post('person/list/$id', {
        'guid': itemId,
        'page': 1,
        'page_size': 200,
      });
      people = [
        for (final person in fnRows(data))
          if (fnText(person, const ['name', 'person_name', 'original_name'])
              case final name?)
            MediaPerson(
              id:
                  fnText(person, const ['person_guid', 'guid', 'item_guid']) ??
                  name,
              name: name,
              role:
                  fnText(person, const [
                    'role',
                    'character',
                    'character_name',
                    'job',
                  ]) ??
                  '',
              type:
                  fnText(person, const [
                    'type',
                    'department',
                    'known_for_department',
                  ]) ??
                  'Actor',
            ),
      ];
    } on AppException catch (error) {
      if (error.kind == FailureKind.auth) rethrow;
    }
    final type = _mapper.type(row, hint: hint);
    final seasonId =
        fnText(row, const [
          'season_guid',
          'seasonGuid',
          'season_id',
          'parent_guid',
        ]) ??
        preview?.seasonId;
    MediaItem? season;
    if (type == MediaType.episode &&
        seasonId != null &&
        preview?.seriesId == null &&
        fnText(row, const [
              'tv_guid',
              'tvGuid',
              'series_guid',
              'seriesGuid',
              'tv_id',
              'series_id',
            ]) ==
            null) {
      season = _knownItems[seasonId];
      if (season?.seriesId == null) {
        try {
          final data = _detail(
            await _api.get('item/${Uri.encodeComponent(seasonId)}'),
          );
          season = _mapper.item(data, id: seasonId, hint: MediaType.season);
          if (season != null) _remember(season);
        } on AppException catch (error) {
          if (error.kind == FailureKind.auth) rethrow;
        }
      }
    }
    final media = _mapper.item(
      row,
      id: itemId,
      hint: hint,
      preview: preview,
      seriesId: season?.seriesId,
      seasonNumber: season?.indexNumber,
      people: people,
    );
    if (media == null) throw const AppException(FailureKind.invalidData);
    return _remember(media);
  }

  static Map<String, dynamic> _detail(Object? data) {
    final object = fnObject(data);
    for (final field in const ['item', 'info', 'detail', 'movie', 'tv']) {
      final nested = fnObject(object[field]);
      if (nested.isNotEmpty) return {...object, ...nested};
    }
    return object;
  }

  static bool _unavailable(AppException error) =>
      error.kind == FailureKind.server &&
      const {404, 501}.contains(error.cause);

  @override
  Future<List<MediaItem>> seasons(String userId, String seriesId) async {
    _check(userId);
    final data = await _api.get('season/list/${Uri.encodeComponent(seriesId)}');
    return _parse(fnRows(data), hint: MediaType.season, seriesId: seriesId)
      ..sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
  }

  @override
  Future<List<MediaItem>> episodes(
    String userId,
    String seriesId, {
    String? seasonId,
  }) async {
    _check(userId);
    final ids = seasonId == null
        ? (await seasons(userId, seriesId)).map((season) => season.id)
        : [seasonId];
    final episodes = <MediaItem>[];
    for (final id in ids) {
      final data = await _api.get('episode/list/${Uri.encodeComponent(id)}');
      episodes.addAll(
        _parse(
          fnRows(data),
          hint: MediaType.episode,
          seriesId: seriesId,
          seasonId: id,
          seasonNumber: _knownItems[id]?.indexNumber,
        )..sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0)),
      );
    }
    return episodes;
  }

  @override
  Future<List<MediaItem>> search(
    String userId,
    String term, {
    int limit = 60,
  }) async {
    _check(userId);
    if (term.trim().isEmpty || limit <= 0) return const [];
    final data = await _api.get('search/list', query: {'q': term.trim()});
    return _parse(fnRows(data))
        .where((item) => item.type != MediaType.season)
        .take(limit)
        .toList();
  }

  @override
  Future<List<MediaItem>> randomItems(String userId, {int limit = 8}) async {
    if (limit <= 0) return const [];
    final libraries = await views(userId)
      ..shuffle();
    final random = Random();
    final values = <String, MediaItem>{};
    const pageSize = 24;
    for (final library in libraries.take(4)) {
      final first = await items(userId, library.id, limit: pageSize);
      final pages = ((first.totalRecordCount ?? 0) + pageSize - 1) ~/ pageSize;
      final start = pages > 1 ? random.nextInt(pages) * pageSize : 0;
      final sampled = start == 0
          ? first
          : await items(userId, library.id, startIndex: start, limit: pageSize);
      for (final item in sampled.items.isEmpty ? first.items : sampled.items) {
        if (item.poster != null) values[item.id] = item;
      }
    }
    return (values.values.toList()..shuffle(random)).take(limit).toList();
  }

  @override
  Future<List<MediaItem>> latest(String userId, {int limit = 12}) async =>
      const [];

  Future<Map<String, dynamic>> _playInfo(String itemId) async =>
      _detail(await _api.post('play/info', {'item_guid': itemId}));

  @override
  Future<List<MediaItem>> resume(String userId, {int limit = 12}) async {
    _check(userId);
    if (limit <= 0) return const [];
    final rows = fnRows(await _api.get('play/list'));
    final seen = <String>{};
    final values = <MediaItem>[];
    for (
      var index = 0;
      index < rows.length && values.length < limit;
      index += 3
    ) {
      final resolved = await Future.wait(
        rows.skip(index).take(3).map((row) async {
          final item = _detail(row);
          final id =
              fnText(row, const ['item_guid']) ?? FnMovieMapper.itemId(item);
          if (id == null || !seen.add(id)) return null;
          Map<String, dynamic> info;
          try {
            info = await _playInfo(id);
          } on AppException catch (error) {
            if (_unavailable(error)) return null;
            rethrow;
          }
          final runtime =
              fnSeconds(info, const ['duration']) ??
              fnSeconds(fnObject(row['video_stream']), const ['duration']) ??
              fnSeconds(item, const ['duration', 'total_duration']);
          final position = _resumePosition(
            fnSeconds(info, const ['ts', 'position', 'playback_position']) ??
                Duration.zero,
            runtime,
          );
          if (position <= Duration.zero) return null;
          return _mapper.item(
            item,
            id: id,
            position: position,
            runtime: runtime,
          );
        }),
      );
      values.addAll(
        resolved.nonNulls
            .where((item) => item.type != MediaType.unknown)
            .map(_remember),
      );
    }
    return values.take(limit).toList();
  }

  static Duration _resumePosition(Duration requested, Duration? runtime) {
    if (requested <= Duration.zero) return Duration.zero;
    if (runtime == null || runtime <= Duration.zero) return requested;
    // Do not resume a completed item, or reset a meaningful position in short clips.
    return requested >= runtime * .98 ? Duration.zero : requested;
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
    final info = await _playInfo(itemId);
    final mediaId = fnText(info, const ['media_guid']);
    if (mediaId == null) throw const AppException(FailureKind.invalidData);
    final stream = fnObject(
      await _api.post('stream', {
        'media_guid': mediaId,
        'ip': 'sakuga',
        'header': {
          'User-Agent': [fnMoviePlaybackUserAgent],
        },
      }),
    );
    final duration =
        fnSeconds(fnObject(stream['video_stream']), const ['duration']) ??
        fnSeconds(info, const ['duration']);
    final position = _resumePosition(
      startPosition ??
          fnSeconds(info, const ['ts', 'position', 'playback_position']) ??
          Duration.zero,
      duration,
    );
    final qualities = fnRows(stream['direct_link_qualities']);
    Uri? selected;
    var maxBitrate = -1.0;
    for (final quality
        in qualities.isEmpty ? fnRows(stream['qualities']) : qualities) {
      final url = fnMovieResourceUri(
        _api.base,
        fnText(quality, const ['url']) ?? '',
      );
      if (url == null || !fnMovieSameOrigin(_api.base, url)) continue;
      final path = url.path.toLowerCase();
      if (!const [
            '.mp4',
            '.mkv',
            '.webm',
            '.mov',
            '.avi',
            '.m4v',
            '.ts',
          ].any(path.endsWith) &&
          !path.contains('/media/range/')) {
        continue;
      }
      final bitrate = fnNumber(quality, const ['bitrate']) ?? 0;
      if (bitrate > maxBitrate) {
        maxBitrate = bitrate;
        selected = url;
      }
    }
    final range = fnMovieEndpoint(
      _api.base,
      'media/range/${Uri.encodeComponent(mediaId)}',
    );
    final proxy = await FnMoviePlaybackProxy.start(
      base: _api.base,
      upstream: selected ?? range,
      fallback: selected != null ? range : null,
      token: server.accessToken,
    );
    return PlaybackSource(
      url: proxy.url,
      headers: const {},
      session: _FnMoviePlaybackSession(this, proxy, itemId, mediaId, duration),
      startPosition: position,
    );
  }

  @override
  Future<void> stopTranscoding(PlaybackSession session) async {
    if (session is _FnMoviePlaybackSession && identical(session.client, this)) {
      await session.proxy.close();
    }
  }

  // fnOS Media has a single progress endpoint, called by updatePlaybackPosition.
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
  Future<void> setPlayed(
    String userId,
    String itemId, {
    required bool played,
  }) async => throw UnsupportedError(
    'Manual watched status is not supported by fnOS Media',
  );

  @override
  Future<void> updatePlaybackPosition(
    String userId,
    String itemId, {
    required Duration position,
    bool? played,
    PlaybackSession? session,
  }) async {
    _check(userId);
    final active =
        session is _FnMoviePlaybackSession &&
            identical(session.client, this) &&
            session.itemId == itemId
        ? session
        : null;
    final info = active == null
        ? await _playInfo(itemId)
        : const <String, dynamic>{};
    final mediaId = active?.mediaId ?? fnText(info, const ['media_guid']);
    if (mediaId == null) throw const AppException(FailureKind.invalidData);
    final duration = active?.duration ?? fnSeconds(info, const ['duration']);
    final target =
        played == true && position == Duration.zero && duration != null
        ? duration
        : position;
    await _api.post('play/record', {
      'item_guid': itemId,
      'media_guid': mediaId,
      'ts': max(0, target.inSeconds),
    }, timeout: const Duration(seconds: 5));
  }
}

class _FnMoviePlaybackSession implements PlaybackSession {
  const _FnMoviePlaybackSession(
    this.client,
    this.proxy,
    this.itemId,
    this.mediaId,
    this.duration,
  );

  final FnMovieClient client;
  final FnMoviePlaybackProxy proxy;
  final String itemId;
  final String mediaId;
  final Duration? duration;
}
