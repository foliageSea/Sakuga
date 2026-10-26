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

  bool get played => userData?['Played'] == true;
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';

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

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final tags = json['ImageTags'];
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
