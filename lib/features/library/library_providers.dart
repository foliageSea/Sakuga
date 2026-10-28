import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../core/logging.dart';
import '../../data/media_server/media_server_client.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_profile.dart';
import '../../data/media_server/server_repository.dart';
import '../player/playback_progress_repository.dart';

typedef LibraryViewQuery = ({String userId, String viewId});

class LibraryQuery {
  const LibraryQuery({
    required this.userId,
    required this.viewId,
    this.genre,
    this.isPlayed,
    this.year,
    this.sort = MediaSort.name,
    this.descending = false,
  });

  final String userId;
  final String viewId;
  final String? genre;
  final bool? isPlayed;
  final int? year;
  final MediaSort sort;
  final bool descending;

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      userId == other.userId &&
      viewId == other.viewId &&
      genre == other.genre &&
      isPlayed == other.isPlayed &&
      year == other.year &&
      sort == other.sort &&
      descending == other.descending;

  @override
  int get hashCode =>
      Object.hash(userId, viewId, genre, isPlayed, year, sort, descending);
}

class LibraryData {
  const LibraryData({
    required this.client,
    required this.userId,
    required this.views,
  });

  final MediaServerClient client;
  final String userId;
  final List<MediaLibrary> views;

  MediaLibrary? viewById(String id) {
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
  final client = ref.watch(mediaServerClientProvider(server));
  if (!client.isConfigured) throw const AppException(FailureKind.auth);
  final users = await client.users();
  if (users.isEmpty) throw const AppException(FailureKind.server);
  final views = await client.views(users.first.id);
  debugPrint('LIB_VIEWS ${views.length}');
  return LibraryData(client: client, userId: users.first.id, views: views);
});

final libraryGenresProvider = FutureProvider.autoDispose
    .family<List<String>, LibraryViewQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.genres(query.userId, query.viewId);
    });

final libraryYearsProvider = FutureProvider.autoDispose
    .family<List<int>, LibraryViewQuery>((ref, query) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.years(query.userId, query.viewId);
    });

class LibraryItemsState {
  const LibraryItemsState({
    required this.items,
    required this.totalRecordCount,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<MediaItem> items;
  final int totalRecordCount;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => items.length < totalRecordCount;

  LibraryItemsState copyWith({
    List<MediaItem>? items,
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
    final loading = current.copyWith(
      loadingMore: true,
      clearLoadMoreError: true,
    );
    state = AsyncData(loading);
    try {
      final data = await ref.read(libraryViewsProvider.future);
      final page = await _fetch(data, startIndex: current.items.length);
      if (!ref.mounted || !identical(state.value, loading)) return;
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
      if (!ref.mounted || !identical(state.value, loading)) return;
      log.warning('Failed to load more items', error, stackTrace);
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: error),
      );
    }
  }

  Future<MediaItemsPage> _fetch(
    LibraryData data, {
    required int startIndex,
  }) async {
    final view = data.viewById(query.viewId);
    final page = await data.client.items(
      query.userId,
      query.viewId,
      startIndex: startIndex,
      limit: pageSize,
      types: _itemTypes(view),
      genre: query.genre,
      isPlayed: query.isPlayed,
      year: query.year,
      sort: query.sort,
      descending: query.descending,
    );
    final items = await ref
        .read(playbackProgressRepositoryProvider)
        .overlayItems(
          page.items,
          serverId: data.client.server.id,
          userId: query.userId,
        );
    return MediaItemsPage(
      items: items,
      totalRecordCount: page.totalRecordCount,
    );
  }

  Set<MediaType> _itemTypes(MediaLibrary? view) => switch (view?.type) {
    MediaLibraryType.tvShows => {MediaType.series},
    MediaLibraryType.movies => {MediaType.movie, MediaType.video},
    MediaLibraryType.musicVideos => {MediaType.musicVideo},
    MediaLibraryType.homeVideos => {MediaType.video},
    _ => {
      MediaType.movie,
      MediaType.series,
      MediaType.episode,
      MediaType.video,
      MediaType.musicVideo,
    },
  };
}

final libraryItemsProvider = AsyncNotifierProvider.autoDispose
    .family<LibraryItemsController, LibraryItemsState, LibraryQuery>(
      LibraryItemsController.new,
    );

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, String>((ref, term) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.search(library.userId, term);
    });
