import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../data/jellyfin/jellyfin_client.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../data/jellyfin/server_profile.dart';
import '../../data/jellyfin/server_repository.dart';

class LibraryData {
  const LibraryData({
    required this.client,
    required this.userId,
    required this.views,
  });

  final JellyfinClient client;
  final String userId;
  final List<JellyfinView> views;
}

final activeServerProvider = Provider<ServerProfile?>((ref) {
  final servers = ref.watch(serversProvider).value;
  if (servers == null || servers.isEmpty) return null;
  return servers.first;
});

final libraryViewsProvider = FutureProvider.autoDispose<LibraryData>((
  ref,
) async {
  final server = ref.watch(activeServerProvider);
  if (server == null) throw const AppException(FailureKind.invalidData);
  if (server.apiKey.isEmpty) throw const AppException(FailureKind.auth);
  final client = JellyfinClient(server: server);
  final users = await client.users();
  if (users.isEmpty) throw const AppException(FailureKind.server);
  final views = await client.views(users.first.id);
  debugPrint('LIB_VIEWS ${views.length}');
  return LibraryData(client: client, userId: users.first.id, views: views);
});

final libraryItemsProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, ({String userId, String viewId})>((
      ref,
      query,
    ) async {
      final data = await ref.watch(libraryViewsProvider.future);
      final items = await data.client.items(query.userId, query.viewId);
      debugPrint('LIB_ITEMS ${items.length}');
      return items;
    });
