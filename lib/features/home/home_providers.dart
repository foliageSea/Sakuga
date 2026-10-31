import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_repository.dart';
import '../../shared/poster_background.dart';
import '../library/library_providers.dart';

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
  return library.client.resume(library.userId);
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
