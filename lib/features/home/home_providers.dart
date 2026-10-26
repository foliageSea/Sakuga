import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_models.dart';
import '../library/library_providers.dart';

final resumeItemsProvider = FutureProvider.autoDispose<List<JellyfinItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  return library.client.resume(library.userId);
});

final latestItemsProvider = FutureProvider.autoDispose<List<JellyfinItem>>((
  ref,
) async {
  final library = await ref.watch(libraryViewsProvider.future);
  return library.client.latest(library.userId);
});
