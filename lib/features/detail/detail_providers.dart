import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/server_profile.dart';
import '../library/library_providers.dart';
import '../player/playback_progress_repository.dart';

typedef ItemQuery = ({String userId, String itemId});
typedef SeriesQuery = ({String userId, String seriesId});
typedef EpisodesQuery = ({String userId, String seriesId, String? seasonId});

/// The episode the primary detail action should open, and whether it resumes
/// a partially watched episode.
typedef NextEpisode = ({MediaItem episode, bool resume});

/// Picks the episode to play from an ordered episode list: the most recently
/// resumed episode, otherwise the first unwatched episode after the last
/// watched one, otherwise the first regular episode.
NextEpisode? resolveNextEpisode(List<MediaItem> episodes) {
  if (episodes.isEmpty) return null;
  final regular = episodes.where((e) => e.parentIndexNumber != 0).toList();
  final candidates = regular.isEmpty ? episodes : regular;
  MediaItem? resumed;
  for (final episode in candidates) {
    final position = episode.playbackPosition;
    if (episode.played || position == null || position <= Duration.zero) {
      continue;
    }
    final current = resumed;
    if (current == null) {
      resumed = episode;
      continue;
    }
    final a = current.lastPlayedAt;
    final b = episode.lastPlayedAt;
    if (b != null && (a == null || b.isAfter(a))) {
      resumed = episode;
    } else if (a == null && b == null) {
      resumed = episode;
    }
  }
  if (resumed != null) return (episode: resumed, resume: true);
  final lastPlayed = candidates.lastIndexWhere((e) => e.played);
  if (lastPlayed >= 0) {
    for (final episode in candidates.skip(lastPlayed + 1)) {
      if (!episode.played) return (episode: episode, resume: false);
    }
  }
  return (episode: candidates.first, resume: false);
}

final libraryItemProvider = FutureProvider.autoDispose
    .family<MediaItem, ItemQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      final item = await library.client.item(query.userId, query.itemId);
      return ref
          .watch(playbackProgressRepositoryProvider)
          .overlayItem(
            item,
            serverId: library.client.server.id,
            userId: query.userId,
          );
    });

final seriesSeasonsProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, SeriesQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.seasons(query.userId, query.seriesId);
    });

final seriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, EpisodesQuery>((ref, query) async {
      final progress = ref.watch(playbackProgressRepositoryProvider);
      final server = ref.watch(activeServerProvider);
      final client =
          server?.type == MediaServerType.ugreen &&
              server?.userId == query.userId
          ? ref.watch(mediaServerClientProvider(server!))
          : (await ref.watch(libraryViewsProvider.future)).client;
      final episodes = await client
          .episodes(query.userId, query.seriesId, seasonId: query.seasonId)
          .timeout(
            const Duration(seconds: 22),
            onTimeout: () {
              throw const AppException(FailureKind.timeout);
            },
          );
      // Local resume data must not keep otherwise available episodes hidden.
      return progress
          .overlayItems(
            episodes,
            serverId: client.server.id,
            userId: query.userId,
          )
          .timeout(const Duration(seconds: 2), onTimeout: () => episodes);
    }, retry: (_, _) => null);
