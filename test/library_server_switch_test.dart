import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';

import 'fakes.dart';

class _Progress extends Fake implements PlaybackProgressRepository {
  @override
  Future<Map<String, int>> loadAll({
    required String serverId,
    required String userId,
  }) async => {};
}

class _Client extends FakeMediaServerClient {
  _Client(ServerProfile server) : super(server: server);

  final pageStarted = Completer<void>();
  final nextPage = Completer<MediaItemsPage>();
  final requests = <({String? genre, int startIndex})>[];
  final queries = <LibraryQuery>[];

  @override
  Future<MediaItemsPage> items(
    String userId,
    String parentId, {
    int startIndex = 0,
    int limit = 60,
    Set<MediaType> types = const {
      MediaType.movie,
      MediaType.series,
      MediaType.episode,
      MediaType.video,
      MediaType.musicVideo,
    },
    MediaSort sort = MediaSort.name,
    String? genre,
    bool? isPlayed,
    int? year,
    bool descending = false,
  }) async {
    requests.add((genre: genre, startIndex: startIndex));
    queries.add(
      LibraryQuery(
        userId: userId,
        viewId: parentId,
        genre: genre,
        isPlayed: isPlayed,
        year: year,
        sort: sort,
        descending: descending,
      ),
    );
    if (startIndex > 0) {
      pageStarted.complete();
      return nextPage.future;
    }
    return MediaItemsPage(
      items: [
        MediaItem(id: 'same-item-id', name: server.name, type: MediaType.movie),
      ],
      totalRecordCount: 2,
    );
  }
}

void main() {
  test('genre pagination retains the filter and isolates late pages', () async {
    const server = ServerProfile(
      id: 'server',
      name: 'Server',
      baseUrl: 'https://media.test',
    );
    final client = _Client(server);
    final container = ProviderContainer(
      overrides: [
        playbackProgressRepositoryProvider.overrideWithValue(_Progress()),
        libraryViewsProvider.overrideWith(
          (ref) async => LibraryData(
            client: client,
            userId: 'user',
            views: const [
              MediaLibrary(
                id: 'view',
                name: 'Movies',
                type: MediaLibraryType.movies,
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final drama = libraryItemsProvider(
      LibraryQuery(
        userId: 'user',
        viewId: 'view',
        genre: 'Drama',
        isPlayed: false,
        year: 2025,
        sort: MediaSort.rating,
        descending: true,
      ),
    );
    final comedy = libraryItemsProvider(
      LibraryQuery(userId: 'user', viewId: 'view', genre: 'Comedy'),
    );
    final dramaSubscription = container.listen(drama, (_, _) {});
    await container.read(drama.future);
    final oldPage = container.read(drama.notifier).loadMore();
    await client.pageStarted.future;
    expect(client.requests, [
      (genre: 'Drama', startIndex: 0),
      (genre: 'Drama', startIndex: 1),
    ]);
    expect(
      client.queries
          .take(2)
          .every(
            (query) =>
                query.isPlayed == false &&
                query.year == 2025 &&
                query.sort == MediaSort.rating &&
                query.descending,
          ),
      isTrue,
    );
    final comedySubscription = container.listen(comedy, (_, _) {});
    addTearDown(comedySubscription.close);
    dramaSubscription.close();
    await container.pump();
    await container.read(comedy.future);
    expect(client.requests.last, (genre: 'Comedy', startIndex: 0));
    client.nextPage.complete(
      const MediaItemsPage(
        items: [
          MediaItem(id: 'old-page', name: 'Old drama', type: MediaType.movie),
        ],
        totalRecordCount: 2,
      ),
    );
    await oldPage;
    expect(container.read(comedy).requireValue.items.map((item) => item.id), [
      'same-item-id',
    ]);
  });

  for (final failOldRequest in [false, true]) {
    test(
      'old pagination cannot replace new server data (error: $failOldRequest)',
      () async {
        const a = ServerProfile(id: 'a', name: 'A', baseUrl: 'http://a.test');
        const b = ServerProfile(id: 'b', name: 'B', baseUrl: 'http://b.test');
        final repository = MemoryServerRepository()..items = [a, b];
        final clients = {'a': _Client(a), 'b': _Client(b)};
        final container = ProviderContainer(
          overrides: [
            serverRepositoryProvider.overrideWithValue(repository),
            playbackProgressRepositoryProvider.overrideWithValue(_Progress()),
            libraryViewsProvider.overrideWith((ref) async {
              final server = ref.watch(activeServerProvider)!;
              return LibraryData(
                client: clients[server.id]!,
                userId: 'same-user',
                views: const [
                  MediaLibrary(
                    id: 'same-view',
                    name: 'Movies',
                    type: MediaLibraryType.movies,
                  ),
                ],
              );
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(serversProvider.future);
        final items = libraryItemsProvider(
          LibraryQuery(userId: 'same-user', viewId: 'same-view', genre: null),
        );
        final subscription = container.listen(items, (_, _) {});
        addTearDown(subscription.close);
        expect((await container.read(items.future)).items.single.name, 'A');
        final oldRequest = container.read(items.notifier).loadMore();
        await clients['a']!.pageStarted.future;
        await container.read(serversProvider.notifier).setActive('b');
        await container.pump();
        expect((await container.read(items.future)).items.single.name, 'B');
        if (failOldRequest) {
          clients['a']!.nextPage.completeError(StateError('old server failed'));
        } else {
          clients['a']!.nextPage.complete(
            const MediaItemsPage(items: [], totalRecordCount: 1),
          );
        }
        await oldRequest;
        final result = container.read(items).requireValue;
        expect(result.items.single.name, 'B');
        expect(result.loadMoreError, isNull);
        expect(result.loadingMore, isFalse);
      },
    );
  }
}
