import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../core/logging.dart';
import '../../data/jellyfin/jellyfin_client.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../data/jellyfin/server_profile.dart';
import '../../data/jellyfin/server_repository.dart';

typedef LibraryQuery = ({String userId, String viewId});

class LibraryData {
  const LibraryData({
    required this.client,
    required this.userId,
    required this.views,
  });

  final JellyfinClient client;
  final String userId;
  final List<JellyfinView> views;

  JellyfinView? viewById(String id) {
    for (final view in views) {
      if (view.id == id) return view;
    }
    return null;
  }
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

class LibraryItemsState {
  const LibraryItemsState({
    required this.items,
    required this.totalRecordCount,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<JellyfinItem> items;
  final int totalRecordCount;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => items.length < totalRecordCount;

  LibraryItemsState copyWith({
    List<JellyfinItem>? items,
    int? totalRecordCount,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) => LibraryItemsState(
    items: items ?? this.items,
    totalRecordCount: totalRecordCount ?? this.totalRecordCount,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}

/// Paged contents of one library view.
///
/// TV libraries are asked for `Series` only; episodes live on the detail page
/// instead of being flattened into the poster grid.
class LibraryItemsController extends AsyncNotifier<LibraryItemsState>
    with LoggingMixin {
  LibraryItemsController(this.query);

  final LibraryQuery query;

  static const pageSize = 60;

  @override
  Future<LibraryItemsState> build() async {
    final data = await ref.watch(libraryViewsProvider.future);
    final page = await _fetch(data, startIndex: 0);
    debugPrint('LIB_ITEMS ${page.items.length}/${page.totalRecordCount}');
    return LibraryItemsState(
      items: page.items,
      totalRecordCount: page.totalRecordCount,
    );
  }

  /// Appends the next page.
  ///
  /// Scroll-driven calls do not retry a page that already failed; the footer
  /// retries explicitly with [retry].
  Future<void> loadMore({bool retry = false}) async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    if (current.loadMoreError != null && !retry) return;
    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final data = await ref.read(libraryViewsProvider.future);
      final page = await _fetch(data, startIndex: current.items.length);
      if (!ref.mounted) return;
      final existingIds = {for (final item in current.items) item.id};
      state = AsyncData(
        LibraryItemsState(
          items: [
            ...current.items,
            for (final item in page.items)
              if (existingIds.add(item.id)) item,
          ],
          totalRecordCount: page.totalRecordCount,
        ),
      );
    } catch (error, stackTrace) {
      if (!ref.mounted) return;
      log.warning('Failed to load more items', error, stackTrace);
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: error),
      );
    }
  }

  Future<JellyfinItemsPage> _fetch(
    LibraryData data, {
    required int startIndex,
  }) {
    final view = data.viewById(query.viewId);
    return data.client.items(
      query.userId,
      query.viewId,
      startIndex: startIndex,
      limit: pageSize,
      includeItemTypes: _includeItemTypes(view),
    );
  }

  String _includeItemTypes(JellyfinView? view) =>
      switch (view?.collectionType) {
        'tvshows' => 'Series',
        'movies' => 'Movie,Video',
        'musicvideos' => 'MusicVideo',
        'homevideos' => 'Video',
        _ => 'Movie,Series,Episode,Video,MusicVideo',
      };
}

final libraryItemsProvider = AsyncNotifierProvider.autoDispose
    .family<LibraryItemsController, LibraryItemsState, LibraryQuery>(
      LibraryItemsController.new,
    );
