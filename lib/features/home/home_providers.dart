import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_models.dart';
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
