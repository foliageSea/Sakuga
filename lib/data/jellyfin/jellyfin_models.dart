class JellyfinUser {
  const JellyfinUser({required this.id, required this.name});

  final String id;
  final String name;

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
  );
}

class JellyfinView {
  const JellyfinView({
    required this.id,
    required this.name,
    required this.collectionType,
  });

  final String id;
  final String name;
  final String? collectionType;

  /// Whether this view is a TV library, whose top-level items are series.
  bool get isTvShows => collectionType == 'tvshows';

  factory JellyfinView.fromJson(Map<String, dynamic> json) => JellyfinView(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    collectionType: json['CollectionType'] as String?,
  );
}

class JellyfinPerson {
  const JellyfinPerson({
    required this.id,
    required this.name,
    required this.role,
    required this.type,
  });

  final String id;
  final String name;
  final String role;
  final String type;

  factory JellyfinPerson.fromJson(Map<String, dynamic> json) => JellyfinPerson(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    role: json['Role'] as String? ?? '',
    type: json['Type'] as String? ?? '',
  );
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    required this.imageTags,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.indexNumber,
    this.parentIndexNumber,
    this.userData,
    this.parentPrimaryImageItemId,
    this.parentPrimaryImageTag,
    this.seriesPrimaryImageTag,
    this.primaryImageAspectRatio,
    this.backdropImageTags = const [],
    this.overview,
    this.genres = const [],
    this.studios = const [],
    this.people = const [],
    this.officialRating,
    this.communityRating,
    this.productionYear,
    this.runTimeTicks,
    this.childCount,
    this.recursiveItemCount,
  });

  final String id;
  final String name;
  final String type;
  final Map<String, String> imageTags;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final int? indexNumber;
  final int? parentIndexNumber;
  final Map<String, dynamic>? userData;

  /// The season/series that owns an episode's poster, when the episode itself
  /// has no primary image.
  final String? parentPrimaryImageItemId;
  final String? parentPrimaryImageTag;
  final String? seriesPrimaryImageTag;

  /// Aspect ratio of the scraped primary image, as reported by the server.
  final double? primaryImageAspectRatio;

  final List<String> backdropImageTags;
  final String? overview;
  final List<String> genres;
  final List<String> studios;
  final List<JellyfinPerson> people;
  final String? officialRating;
  final double? communityRating;
  final int? productionYear;
  final int? runTimeTicks;

  /// Direct children: seasons for a series, episodes for a season.
  final int? childCount;

  /// Every descendant: episodes for a series.
  final int? recursiveItemCount;

  bool get played => userData?['Played'] == true;
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';

  /// Saved resume position in 100ns ticks, when present.
  int? get playbackPositionTicks {
    final value = userData?['PlaybackPositionTicks'];
    return value is num ? value.toInt() : null;
  }

  /// Watched fraction (0–100) as reported by the server, for resume bars.
  double? get playedPercentage {
    final value = userData?['PlayedPercentage'];
    if (value is num) return value.toDouble();
    final ticks = playbackPositionTicks;
    final runtime = runTimeTicks;
    if (ticks != null && ticks > 0 && runtime != null && runtime > 0) {
      return (ticks * 100 / runtime).clamp(0.0, 100.0);
    }
    return null;
  }

  /// Active watch progress in `0.0..1.0`, or null when unwatched or finished.
  double? get progressFraction {
    if (isSeries && played) return null;
    final percentage = playedPercentage;
    if (percentage == null || percentage <= 0) return null;
    return (percentage / 100).clamp(0.0, 1.0);
  }

  JellyfinItem withPlaybackPosition(int positionTicks, {bool? played}) {
    final completed = played == true || positionTicks <= 0;
    final normalizedTicks = completed ? 0 : positionTicks;
    final data = <String, dynamic>{
      ...?userData,
      'PlaybackPositionTicks': normalizedTicks,
      if (played != null) 'Played': played else if (completed) 'Played': true,
    };
    final runtime = runTimeTicks;
    if (completed) {
      data.remove('PlayedPercentage');
    } else if (runtime != null && runtime > 0) {
      data['PlayedPercentage'] = (normalizedTicks * 100 / runtime).clamp(
        0.0,
        100.0,
      );
    }
    return JellyfinItem(
      id: id,
      name: name,
      type: type,
      imageTags: imageTags,
      seriesId: seriesId,
      seriesName: seriesName,
      seasonId: seasonId,
      indexNumber: indexNumber,
      parentIndexNumber: parentIndexNumber,
      userData: data,
      parentPrimaryImageItemId: parentPrimaryImageItemId,
      parentPrimaryImageTag: parentPrimaryImageTag,
      seriesPrimaryImageTag: seriesPrimaryImageTag,
      primaryImageAspectRatio: primaryImageAspectRatio,
      backdropImageTags: backdropImageTags,
      overview: overview,
      genres: genres,
      studios: studios,
      people: people,
      officialRating: officialRating,
      communityRating: communityRating,
      productionYear: productionYear,
      runTimeTicks: runTimeTicks,
      childCount: childCount,
      recursiveItemCount: recursiveItemCount,
    );
  }

  /// Title to show on a card: the series for episodes, the item itself
  /// otherwise.
  String get displayTitle => isEpisode ? (seriesName ?? name) : name;

  /// Secondary card line: the episode itself for episodes.
  String? get displaySubtitle {
    if (!isEpisode) return null;
    final code = episodeCode;
    return code == null ? name : '$code · $name';
  }

  /// `S01E03` when the season is known, `E03` otherwise.
  String? get episodeCode {
    final episode = indexNumber;
    if (episode == null) return null;
    final season = parentIndexNumber;
    final padded = episode.toString().padLeft(2, '0');
    return season == null
        ? 'E$padded'
        : 'S${season.toString().padLeft(2, '0')}E$padded';
  }

  /// The scraped aspect ratio, falling back to a 16:9 frame.
  double get thumbnailAspectRatio {
    final ratio = primaryImageAspectRatio;
    if (ratio == null || ratio < 0.5 || ratio > 3) return 16 / 9;
    return ratio;
  }

  /// Scraped poster shape, falling back to a conventional 2:3 poster.
  double get posterAspectRatio {
    final ratio = primaryImageAspectRatio;
    if (ratio == null || ratio < 0.5 || ratio > 3) return 2 / 3;
    return ratio;
  }

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final tags = json['ImageTags'];
    final backdrops = json['BackdropImageTags'];
    final genres = json['Genres'];
    final studios = json['Studios'];
    final people = json['People'];
    return JellyfinItem(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String? ?? '',
      imageTags: tags is Map
          ? tags.map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonId: json['SeasonId'] as String?,
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      userData: json['UserData'] is Map<String, dynamic>
          ? json['UserData'] as Map<String, dynamic>
          : null,
      parentPrimaryImageItemId: json['ParentPrimaryImageItemId'] as String?,
      parentPrimaryImageTag: json['ParentPrimaryImageTag'] as String?,
      seriesPrimaryImageTag: json['SeriesPrimaryImageTag'] as String?,
      primaryImageAspectRatio: (json['PrimaryImageAspectRatio'] as num?)
          ?.toDouble(),
      backdropImageTags: backdrops is List
          ? backdrops.map((value) => value.toString()).toList()
          : const [],
      overview: json['Overview'] as String?,
      genres: genres is List
          ? genres.map((value) => value.toString()).toList()
          : const [],
      studios: studios is List
          ? studios
                .whereType<Map<String, dynamic>>()
                .map((value) => value['Name'] as String? ?? '')
                .where((value) => value.isNotEmpty)
                .toList()
          : const [],
      people: people is List
          ? people
                .whereType<Map<String, dynamic>>()
                .map(JellyfinPerson.fromJson)
                .where((person) => person.name.isNotEmpty)
                .toList()
          : const [],
      officialRating: json['OfficialRating'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      childCount: (json['ChildCount'] as num?)?.toInt(),
      recursiveItemCount: (json['RecursiveItemCount'] as num?)?.toInt(),
    );
  }
}

class JellyfinItemsPage {
  const JellyfinItemsPage({
    required this.items,
    required this.totalRecordCount,
  });

  final List<JellyfinItem> items;
  final int totalRecordCount;
}
