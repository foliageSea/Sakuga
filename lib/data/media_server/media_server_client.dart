import 'media_models.dart';
import 'playback_models.dart';
import 'server_profile.dart';

abstract interface class MediaServerClient {
  ServerProfile get server;
  bool get isConfigured;
  Future<List<MediaUser>> users();
  Future<List<MediaLibrary>> views(String userId);
  Future<List<String>> genres(String userId, String parentId);
  Future<List<int>> years(String userId, String parentId);
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
  });
  Future<MediaItem> item(String userId, String itemId);
  Future<List<MediaItem>> seasons(String userId, String seriesId);
  Future<List<MediaItem>> episodes(
    String userId,
    String seriesId, {
    String? seasonId,
  });
  Future<List<MediaItem>> resume(String userId, {int limit = 12});
  Future<List<MediaItem>> latest(String userId, {int limit = 12});
  Future<List<MediaItem>> randomItems(String userId, {int limit = 8});
  Future<List<MediaItem>> search(String userId, String term, {int limit = 60});
  Future<PlaybackSource> playbackSource(
    String userId,
    String itemId, {
    Duration startPosition = Duration.zero,
  });
  Future<void> reportPlaybackStarted(
    PlaybackSession session, {
    required Duration position,
    required bool isPaused,
    double volume = 100,
  });
  Future<void> reportPlaybackProgress(
    PlaybackSession session, {
    required Duration position,
    required bool isPaused,
    double volume = 100,
  });
  Future<void> reportPlaybackStopped(
    PlaybackSession session, {
    required Duration position,
    required bool failed,
    double volume = 100,
  });
  Future<void> setPlayed(String userId, String itemId, {required bool played});
  Future<void> updatePlaybackPosition(
    String userId,
    String itemId, {
    required Duration position,
    bool? played,
  });
}
