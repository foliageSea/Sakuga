import '../media_server/media_models.dart';

Duration jellyfinDuration(int ticks) => Duration(microseconds: ticks ~/ 10);
int jellyfinTicks(Duration duration) => duration.inMicroseconds * 10;

class JellyfinMapper {
  const JellyfinMapper({required this.baseUrl, required this.headers});
  final String baseUrl;
  final Map<String, String> headers;

  MediaUser user(Map<String, dynamic> json) => MediaUser(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
  );
  MediaLibrary library(Map<String, dynamic> json) => MediaLibrary(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    type: switch (json['CollectionType']) {
      'movies' => MediaLibraryType.movies,
      'tvshows' => MediaLibraryType.tvShows,
      'musicvideos' => MediaLibraryType.musicVideos,
      'homevideos' => MediaLibraryType.homeVideos,
      _ => MediaLibraryType.unknown,
    },
  );

  static String itemType(MediaType type) => switch (type) {
    MediaType.movie => 'Movie',
    MediaType.series => 'Series',
    MediaType.season => 'Season',
    MediaType.episode => 'Episode',
    MediaType.video => 'Video',
    MediaType.musicVideo => 'MusicVideo',
    MediaType.unknown => 'Unknown',
  };

  MediaItem item(Map<String, dynamic> json) {
    final userData = json['UserData'] as Map<String, dynamic>? ?? const {};
    final id = json['Id'] as String? ?? '';
    final tags = json['ImageTags'] as Map? ?? const {};
    MediaImageResource? poster = _image(id, tags['Primary']);
    poster ??= _image(
      json['ParentPrimaryImageItemId'],
      json['ParentPrimaryImageTag'],
    );
    poster ??= _image(json['SeriesId'], json['SeriesPrimaryImageTag']);
    final backdrops = json['BackdropImageTags'] as List? ?? const [];
    return MediaItem(
      id: id,
      name: json['Name'] as String? ?? '',
      type: MediaType.values.firstWhere(
        (type) => itemType(type) == json['Type'],
        orElse: () => MediaType.unknown,
      ),
      poster: poster,
      backdrop: backdrops.isEmpty
          ? null
          : _image(id, backdrops.first, kind: 'Backdrop/0'),
      logo:
          _image(id, tags['Logo'], kind: 'Logo') ??
          _image(
            json['ParentLogoItemId'],
            json['ParentLogoImageTag'],
            kind: 'Logo',
          ),
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonId: json['SeasonId'] as String?,
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      played: userData['Played'] == true,
      playbackPosition: _duration(userData['PlaybackPositionTicks']),
      reportedPlayedPercentage: (userData['PlayedPercentage'] as num?)
          ?.toDouble(),
      primaryImageAspectRatio: (json['PrimaryImageAspectRatio'] as num?)
          ?.toDouble(),
      overview: json['Overview'] as String?,
      genres: (json['Genres'] as List? ?? const []).cast<String>(),
      studios: (json['Studios'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((studio) => studio['Name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(),
      people: (json['People'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (person) => MediaPerson(
              id: person['Id'] as String? ?? '',
              name: person['Name'] as String? ?? '',
              role: person['Role'] as String? ?? '',
              type: person['Type'] as String? ?? '',
            ),
          )
          .where((person) => person.name.isNotEmpty)
          .toList(),
      officialRating: json['OfficialRating'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      runtime: _duration(json['RunTimeTicks']),
      childCount: (json['ChildCount'] as num?)?.toInt(),
      recursiveItemCount: (json['RecursiveItemCount'] as num?)?.toInt(),
    );
  }

  Duration? _duration(Object? value) =>
      value is num ? jellyfinDuration(value.toInt()) : null;

  MediaImageResource? _image(
    Object? id,
    Object? tag, {
    String kind = 'Primary',
  }) {
    if (id is! String || id.isEmpty || tag is! String || tag.isEmpty) {
      return null;
    }
    final url =
        '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/Items/${Uri.encodeComponent(id)}/Images/$kind';
    // PNG preserves the transparent background of title artwork.
    final format = kind == 'Logo' ? '&format=Png' : '';
    return MediaImageResource(
      urlTemplate:
          '$url?maxWidth={width}&tag=${Uri.encodeQueryComponent(tag)}$format',
      cacheKey: '$url?tag=${Uri.encodeQueryComponent(tag)}$format',
      headers: headers,
    );
  }
}
