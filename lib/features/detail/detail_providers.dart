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
