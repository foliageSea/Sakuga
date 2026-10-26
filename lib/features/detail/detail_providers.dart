import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_models.dart';
import '../library/library_providers.dart';

typedef ItemQuery = ({String userId, String itemId});
typedef SeriesQuery = ({String userId, String seriesId});
typedef EpisodesQuery = ({String userId, String seriesId, String? seasonId});

final libraryItemProvider = FutureProvider.autoDispose
    .family<JellyfinItem, ItemQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.item(query.userId, query.itemId);
    });

final seriesSeasonsProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, SeriesQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.seasons(query.userId, query.seriesId);
    });

final seriesEpisodesProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, EpisodesQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.episodes(
        query.userId,
        query.seriesId,
        seasonId: query.seasonId,
      );
    });
