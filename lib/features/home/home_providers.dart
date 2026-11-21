import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_profile.dart';
import '../../data/media_server/server_repository.dart';
import '../../shared/poster_background.dart';
import '../library/library_providers.dart';
import '../player/playback_progress_repository.dart';

void refreshHome(WidgetRef ref) {
  ref.invalidate(libraryViewsProvider);
  ref.invalidate(randomItemsProvider);
  ref.invalidate(resumeItemsProvider);
  ref.invalidate(latestItemsProvider);
}

final resumeItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  final client = library.client;
  if (client.server.type.syncsPlaybackProgress) {
    return client.resume(library.userId);
  }
  const limit = 12;
  final repository = ref.read(playbackProgressRepositoryProvider);
  final local = await repository.tryLoadAllEntries(
    serverId: client.server.id,
    userId: library.userId,
  );
  List<MediaItem> remote;
  try {
    remote = await client.resume(library.userId, limit: limit);
  } catch (_) {
    if (!local.values.any((entry) => entry.positionTicks > 0)) rethrow;
    remote = const [];
  }
  final remoteById = {
    for (final item in remote)
      if (local[item.id]?.positionTicks != 0) item.id: item,
  };
  final candidates =
      {
          ...remoteById.keys,
          for (final entry in local.entries)
            if (entry.value.positionTicks > 0) entry.key,
        }.map((id) {
          final localDate = local[id]?.lastPlayedAt;
          final remoteDate = remoteById[id]?.lastPlayedAt;
          final lastPlayedAt =
              localDate != null &&
                  (remoteDate == null || localDate.isAfter(remoteDate))
              ? localDate
              : remoteDate;
          return (id: id, lastPlayedAt: lastPlayedAt);
        }).toList()
        ..sort((a, b) {
          final aDate = a.lastPlayedAt;
          final bDate = b.lastPlayedAt;
          if (aDate == null && bDate != null) return 1;
          if (aDate != null && bDate == null) return -1;
          final byDate = aDate == null ? 0 : bDate!.compareTo(aDate);
          return byDate == 0 ? a.id.compareTo(b.id) : byDate;
        });

  // Sort before fetching details so an unordered local store cannot affect
  // which items make the cut. Bound lookups for entries absent from the NAS list.
  var remainingLookups = limit;
  final items = await Future.wait(
    candidates.map((candidate) async {
      final id = candidate.id;
      var item = remoteById[id];
      if (item == null) {
        if (remainingLookups == 0) return null;
        remainingLookups--;
        try {
          item = await client.item(library.userId, id);
        } catch (_) {
          return null;
        }
      }
      final ticks = local[id]?.positionTicks ?? 0;
      return ticks > 0
          ? item.withPlaybackPosition(Duration(microseconds: ticks ~/ 10))
          : item;
    }),
  );
  return items.whereType<MediaItem>().take(limit).toList();
});

final latestItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  return library.client.latest(library.userId);
});

final randomItemsProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  final items = await library.client.randomItems(library.userId);
  // UGREEN already ranks by backdrop and filters out items without artwork.
  if (library.client.server.type == MediaServerType.ugreen) return items;
  final withPosters = items.where((item) => item.poster != null).toList();
  return withPosters.isNotEmpty ? withPosters : items;
});

class HomeCarouselIndex extends Notifier<int> {
  @override
  int build() {
    ref.watch(randomItemsProvider);
    return 0;
  }

  void set(int index) {
    if (state != index) state = index;
  }
}

final homeCarouselIndexProvider =
    NotifierProvider.autoDispose<HomeCarouselIndex, int>(HomeCarouselIndex.new);

/// Resolves the active home carousel slide's poster for the global window
/// background shared by the home and library root routes.
PosterBackground? watchHomePosterBackground(WidgetRef ref) {
  final servers = ref.watch(serversProvider).value;
  if (servers == null || servers.isEmpty) {
    return null;
  }
  final library = ref.watch(libraryViewsProvider).value;
  if (library == null) return null;
  final items = ref.watch(randomItemsProvider).value;
  if (items == null || items.isEmpty) return null;
  final index = ref.watch(homeCarouselIndexProvider).clamp(0, items.length - 1);
  final url = items[index].poster?.url();
  if (url == null) return null;
  return PosterBackground(
    url: url,
    headers: items[index].poster?.headers ?? const {},
  );
}
