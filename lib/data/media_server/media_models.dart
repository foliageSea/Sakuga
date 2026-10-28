enum MediaType { movie, series, season, episode, video, musicVideo, unknown }

enum MediaLibraryType { movies, tvShows, musicVideos, homeVideos, unknown }

enum MediaSort { name, random }

class MediaUser {
  const MediaUser({required this.id, required this.name});
  final String id;
  final String name;
}

class MediaLibrary {
  const MediaLibrary({
    required this.id,
    required this.name,
    this.type = MediaLibraryType.unknown,
  });
  final String id;
  final String name;
  final MediaLibraryType type;
  bool get isTvShows => type == MediaLibraryType.tvShows;
}

/// A server-resolved image. The template may contain `{width}`.
class MediaImageResource {
  const MediaImageResource({
    required this.urlTemplate,
    required this.cacheKey,
    this.headers = const {},
  });
  final String urlTemplate;
  final String cacheKey;
  final Map<String, String> headers;
  String url({int width = 600}) =>
      urlTemplate.replaceAll('{width}', width.toString());
}

class MediaPerson {
  const MediaPerson({
    required this.id,
    required this.name,
    required this.role,
    required this.type,
  });
  final String id;
  final String name;
  final String role;
  final String type;
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.poster,
    this.backdrop,
    this.logo,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.indexNumber,
    this.parentIndexNumber,
    this.played = false,
    this.playbackPosition,
    this.reportedPlayedPercentage,
    this.primaryImageAspectRatio,
    this.overview,
    this.genres = const [],
    this.studios = const [],
    this.people = const [],
    this.officialRating,
    this.communityRating,
    this.productionYear,
    this.runtime,
    this.childCount,
    this.recursiveItemCount,
  });

  final String id;
  final String name;
  final MediaType type;
  final MediaImageResource? poster;
  final MediaImageResource? backdrop;
  final MediaImageResource? logo;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final int? indexNumber;
  final int? parentIndexNumber;
  final bool played;
  final Duration? playbackPosition;
  final double? reportedPlayedPercentage;
  final double? primaryImageAspectRatio;
  final String? overview;
  final List<String> genres;
  final List<String> studios;
  final List<MediaPerson> people;
  final String? officialRating;
  final double? communityRating;
  final int? productionYear;
  final Duration? runtime;
  final int? childCount;
  final int? recursiveItemCount;

  bool get isSeries => type == MediaType.series;
  bool get isEpisode => type == MediaType.episode;

  double? get playedPercentage {
    if (reportedPlayedPercentage != null) return reportedPlayedPercentage;
    final position = playbackPosition?.inMicroseconds;
    final duration = runtime?.inMicroseconds;
    if (position != null && position > 0 && duration != null && duration > 0) {
      return (position * 100 / duration).clamp(0.0, 100.0);
    }
    return null;
  }

  double? get progressFraction {
    if (isSeries && played) return null;
    final percentage = playedPercentage;
    if (percentage == null || percentage <= 0) return null;
    return (percentage / 100).clamp(0.0, 1.0);
  }

  MediaItem withPlaybackPosition(Duration position, {bool? played}) {
    final completed = played == true || position <= Duration.zero;
    return MediaItem(
      id: id,
      name: name,
      type: type,
      poster: poster,
      backdrop: backdrop,
      logo: logo,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonId: seasonId,
      indexNumber: indexNumber,
      parentIndexNumber: parentIndexNumber,
      played: played ?? (completed ? true : this.played),
      playbackPosition: completed ? Duration.zero : position,
      primaryImageAspectRatio: primaryImageAspectRatio,
      overview: overview,
      genres: genres,
      studios: studios,
      people: people,
      officialRating: officialRating,
      communityRating: communityRating,
      productionYear: productionYear,
      runtime: runtime,
      childCount: childCount,
      recursiveItemCount: recursiveItemCount,
    );
  }

  String get displayTitle => isEpisode ? (seriesName ?? name) : name;
  String? get displaySubtitle {
    if (!isEpisode) return null;
    final code = episodeCode;
    return code == null ? name : '$code · $name';
  }

  String? get episodeCode {
    final episode = indexNumber;
    if (episode == null) return null;
    final season = parentIndexNumber;
    final padded = episode.toString().padLeft(2, '0');
    return season == null
        ? 'E$padded'
        : 'S${season.toString().padLeft(2, '0')}E$padded';
  }

  double get thumbnailAspectRatio => _aspectRatio(16 / 9);
  double get posterAspectRatio => _aspectRatio(2 / 3);
  double _aspectRatio(double fallback) {
    final ratio = primaryImageAspectRatio;
    return ratio == null || ratio < 0.5 || ratio > 3 ? fallback : ratio;
  }
}

class MediaItemsPage {
  const MediaItemsPage({required this.items, required this.totalRecordCount});
  final List<MediaItem> items;
  final int totalRecordCount;
}
