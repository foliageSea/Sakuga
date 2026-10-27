import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media_server/media_models.dart';
import '../library/library_providers.dart';
import '../player/playback_progress_repository.dart';

typedef ItemQuery = ({String userId, String itemId});
typedef SeriesQuery = ({String userId, String seriesId});
typedef EpisodesQuery = ({String userId, String seriesId, String? seasonId});

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
      final library = await ref.watch(libraryViewsProvider.future);
      final episodes = await library.client.episodes(
        query.userId,
        query.seriesId,
        seasonId: query.seasonId,
      );
      return ref
          .watch(playbackProgressRepositoryProvider)
          .overlayItems(
            episodes,
            serverId: library.client.server.id,
            userId: query.userId,
          );
    });
