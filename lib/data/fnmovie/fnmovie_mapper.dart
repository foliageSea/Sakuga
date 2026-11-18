import '../media_server/media_models.dart';
import 'fnmovie_protocol.dart';

Map<String, dynamic> fnObject(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<Map<String, dynamic>> fnRows(Object? value) {
  if (value is List) return value.whereType<Map<String, dynamic>>().toList();
  final object = fnObject(value);
  for (final key in const [
    'list',
    'items',
    'records',
    'results',
    'rows',
    'data',
    'persons',
    'episodes',
    'seasons',
    'medias',
    'movies',
    'tv',
  ]) {
    if (object[key] case final List values) return fnRows(values);
    if (object[key] case final Map<String, dynamic> nested) {
      final rows = fnRows(nested);
      if (rows.isNotEmpty) return rows;
    }
  }
  return const [];
}

String? fnText(Map<String, dynamic> object, List<String> keys) {
  for (final key in keys) {
    final value = object[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}

double? fnNumber(Map<String, dynamic> object, List<String> keys) {
  final value = double.tryParse(fnText(object, keys) ?? '');
  return value != null && value.isFinite ? value : null;
}

Duration? fnSeconds(Map<String, dynamic> object, List<String> keys) {
  final value = fnNumber(object, keys);
  return value != null && value >= 0 && value < 1e10
      ? Duration(microseconds: (value * Duration.microsecondsPerSecond).round())
      : null;
}

String? _imagePath(Object? value) => switch (value) {
  final String path when path.trim().isNotEmpty => path.trim(),
  final List paths => paths.map(_imagePath).nonNulls.firstOrNull,
  final Map<String, dynamic> object => fnText(object, const [
    'url',
    'path',
    'src',
    'image',
    'poster_path',
    'profile_path',
    'file',
  ]),
  _ => null,
};

class FnMovieMapper {
  const FnMovieMapper(this.base, this.token, this.profileId);

  final Uri base;
  final String token;
  final String profileId;

  static String? itemId(Map<String, dynamic> object) =>
      fnText(object, const ['guid', 'id', 'item_guid']);

  static String? libraryId(Map<String, dynamic> object) {
    final id = fnText(object, const [
      'mdb_guid',
      'mdbGuid',
      'mdb_id',
      'mdbId',
      'mediadb_guid',
      'mediadbGuid',
      'mediadb_id',
      'mediadbId',
      'library_guid',
      'libraryGuid',
      'library_id',
      'libraryId',
      'ancestor_guid',
      'ancestorGuid',
    ]);
    if (id != null) return id;
    for (final key in const ['mdb', 'mediadb', 'library', 'ancestor']) {
      final nested = fnText(fnObject(object[key]), const ['guid', 'id']);
      if (nested != null) return nested;
    }
    return null;
  }

  MediaLibrary? library(Map<String, dynamic> object) {
    final id = fnText(object, const ['guid', 'id', 'mdb_guid']);
    final name = fnText(object, const ['name', 'title']);
    if (id == null || name == null) return null;
    final type = fnText(object, const ['category', 'type', 'view_type']);
    return MediaLibrary(
      id: id,
      name: name,
      type: switch (type?.toLowerCase()) {
        'movie' || 'movies' => MediaLibraryType.movies,
        'tv' || 'tvshows' || 'series' => MediaLibraryType.tvShows,
        _ => MediaLibraryType.unknown,
      },
    );
  }

  MediaType type(Map<String, dynamic> object, {MediaType? hint}) {
    var video = false;
    for (final key in const [
      'type',
      'media_type',
      'mediaType',
      'category',
      'item_type',
      'itemType',
    ]) {
      final value = fnText(object, [key])?.toLowerCase() ?? '';
      switch (value) {
        case 'directory' ||
            'folder' ||
            'livechannel' ||
            'person' ||
            'actor' ||
            'cast':
          return MediaType.unknown;
        case 'movie' || 'film':
          return MediaType.movie;
        case 'tv' || 'series' || 'show' || 'tvshow':
          return MediaType.series;
        case 'season':
          return MediaType.season;
        case 'episode':
          return MediaType.episode;
        case 'video':
          video = true;
      }
    }
    if (hint == MediaType.season || hint == MediaType.episode) return hint!;
    if (fnNumber(object, const ['episode_number', 'episodeNumber']) != null ||
        fnText(object, const [
              'season_guid',
              'seasonGuid',
              'season_id',
              'tv_guid',
              'tvGuid',
              'series_guid',
              'seriesGuid',
            ]) !=
            null) {
      return MediaType.episode;
    }
    return hint ?? (video ? MediaType.video : MediaType.unknown);
  }

  MediaItem? item(
    Map<String, dynamic> object, {
    MediaType? hint,
    String? id,
    String? seriesId,
    String? seasonId,
    int? seasonNumber,
    MediaItem? preview,
    Duration? position,
    Duration? runtime,
    List<MediaPerson> people = const [],
  }) {
    final guid = id ?? itemId(object);
    final kind = type(object, hint: hint);
    final episodeNumber = fnNumber(object, const [
      'episode_number',
      'episodeNumber',
    ])?.toInt();
    final seasonIndex =
        fnNumber(object, const [
          'season_number',
          'seasonNumber',
          'number',
        ])?.toInt() ??
        seasonNumber;
    final name =
        fnText(object, const [
          'title',
          'name',
          'original_title',
          'display_name',
          'file_name',
        ]) ??
        preview?.name ??
        switch (kind) {
          MediaType.season when seasonIndex != null => '$seasonIndex',
          MediaType.episode when episodeNumber != null => '$episodeNumber',
          _ => null,
        };
    if (guid == null || name == null) return null;
    final year = fnText(object, const [
      'year',
      'release_date',
      'air_date',
      'first_air_date',
    ]);
    final watched = const [
      'true',
      '1',
    ].contains('${object['is_watched'] ?? object['watched']}'.toLowerCase());
    final parent = fnText(object, const ['parent_guid', 'parentGuid']);
    return MediaItem(
      id: guid,
      name: name,
      type: kind,
      poster:
          _image(object, const [
            'poster',
            'posters',
            'poster_list',
            'poster_url',
            'posterUrl',
            'image',
            'image_url',
            'cover',
            'poster_path',
            'posterPath',
            'thumb',
            'still_path',
          ]) ??
          preview?.poster,
      seriesPoster:
          _image(object, const ['tv_poster', 'series_poster']) ??
          preview?.seriesPoster,
      backdrop:
          _image(object, const [
            'backdrops',
            'backdrop',
            'backdrop_path',
            'backdrop_url',
          ]) ??
          preview?.backdrop,
      logo:
          _image(object, const ['logos', 'logo', 'logo_path', 'logo_url']) ??
          preview?.logo,
      seriesId:
          seriesId ??
          fnText(object, const [
            'tv_guid',
            'tvGuid',
            'series_guid',
            'seriesGuid',
            'tv_id',
            'series_id',
          ]) ??
          (kind == MediaType.season ? parent : null) ??
          preview?.seriesId,
      seriesName:
          fnText(object, const [
            'tv_title',
            'tvTitle',
            'series_title',
            'seriesTitle',
            'show_title',
          ]) ??
          preview?.seriesName,
      seasonId:
          seasonId ??
          fnText(object, const ['season_guid', 'seasonGuid', 'season_id']) ??
          (kind == MediaType.episode ? parent : null) ??
          preview?.seasonId,
      indexNumber:
          (kind == MediaType.season ? seasonIndex : episodeNumber) ??
          preview?.indexNumber,
      parentIndexNumber: kind == MediaType.episode
          ? seasonIndex ?? preview?.parentIndexNumber
          : null,
      played: watched,
      // Only /play/info supplies an authoritative watch position.
      playbackPosition: position,
      runtime:
          runtime ??
          fnSeconds(object, const ['duration', 'total_duration']) ??
          preview?.runtime,
      overview: fnText(object, const [
        'overview',
        'description',
        'summary',
        'plot',
      ]),
      genres: switch (object['genres']) {
        final List genres => [
          for (final genre in genres)
            if ((genre is String
                    ? genre
                    : fnText(fnObject(genre), const ['name', 'title']))
                case final String name)
              name,
        ],
        _ => const [],
      },
      people: people,
      communityRating: fnNumber(object, const [
        'rating',
        'score',
        'vote_average',
      ]),
      productionYear: year != null && year.length >= 4
          ? int.tryParse(year.substring(0, 4))
          : null,
    );
  }

  MediaImageResource? _image(Map<String, dynamic> object, List<String> keys) {
    final path = keys
        .map((key) => _imagePath(object[key]))
        .nonNulls
        .firstOrNull;
    if (path == null) return null;
    final url = fnMovieResourceUri(
      base,
      path.startsWith('/') ||
              path.contains('://') ||
              path.startsWith('api/') ||
              path.startsWith('sys/img/')
          ? (path.startsWith('sys/img/') || path.startsWith('/sys/img/')
                ? '/api/v1/${path.replaceFirst(RegExp(r'^/'), '')}'
                : path)
          : '/api/v1/sys/img/$path',
    );
    if (url == null) return null;
    return MediaImageResource(
      urlTemplate: '$url',
      cacheKey: 'fnmovie:$profileId:$url',
      headers: {
        fnMovieArtworkProfileHeader: profileId,
        if (fnMovieSameOrigin(base, url)) ...{
          fnMovieArtworkOriginHeader: base.origin,
          'Authorization': token,
        },
      },
    );
  }
}
