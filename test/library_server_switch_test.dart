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
  }) async {
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
        final items = libraryItemsProvider((
          userId: 'same-user',
          viewId: 'same-view',
        ));
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
