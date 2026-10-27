import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_models.dart';
import '../../data/jellyfin/server_repository.dart';
import '../../shared/poster_background.dart';
import '../library/library_providers.dart';
import '../player/playback_progress_repository.dart';

final resumeItemsProvider = FutureProvider.autoDispose<List<JellyfinItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  final serverItems = await library.client.resume(library.userId);
  final pending = await ref
      .watch(playbackProgressRepositoryProvider)
      .tryLoadAll(serverId: library.client.server.id, userId: library.userId);
  if (pending.isEmpty) return serverItems;

  final byId = {for (final item in serverItems) item.id: item};
  for (final entry in pending.entries) {
    if (entry.value <= 0) {
      byId.remove(entry.key);
      continue;
    }
    final item = byId[entry.key];
    if (item != null) {
      byId[entry.key] = item.withPlaybackPosition(entry.value);
      continue;
    }
    try {
      final fetched = await library.client.item(library.userId, entry.key);
      if (fetched.id.isNotEmpty) {
        byId[entry.key] = fetched.withPlaybackPosition(entry.value);
      }
    } catch (_) {
      // Keep the server-provided row usable if one pending item cannot load.
    }
  }
  return byId.values.toList();
});

final latestItemsProvider = FutureProvider.autoDispose<List<JellyfinItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  return library.client.latest(library.userId);
});

final randomItemsProvider = FutureProvider.autoDispose<List<JellyfinItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  final items = await library.client.randomItems(library.userId);
  final withPosters = items
      .where((item) => library.client.imageUrl(item) != null)
      .toList();
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
  if (servers == null || servers.isEmpty || servers.first.apiKey.isEmpty) {
    return null;
  }
  final library = ref.watch(libraryViewsProvider).value;
  if (library == null) return null;
  final items = ref.watch(randomItemsProvider).value;
  if (items == null || items.isEmpty) return null;
  final index = ref.watch(homeCarouselIndexProvider).clamp(0, items.length - 1);
  final url = library.client.imageUrl(items[index]);
  if (url == null) return null;
  return PosterBackground(url: url, headers: library.client.authHeaders);
}
