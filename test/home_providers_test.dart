import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';

import 'fakes.dart';

class _Client extends FakeMediaServerClient {
  _Client()
    : super(
        server: const ServerProfile(
          id: 'server',
          name: 'Server',
          baseUrl: 'https://media.test',
          apiKey: 'key',
        ),
      );

  List<MediaItem> result = [
    for (final id in ['episode-4', 'episode-5'])
      MediaItem(
        id: id,
        name: id,
        type: MediaType.episode,
        seriesId: 'series',
        seasonId: 'season',
        parentIndexNumber: 1,
      ),
    const MediaItem(id: 'movie', name: 'Movie', type: MediaType.movie),
  ];
  int calls = 0;

  @override
  Future<List<MediaItem>> resume(String userId, {int limit = 12}) async {
    expect(userId, 'user');
    calls++;
    return result;
  }
}

class _Progress extends Fake implements PlaybackProgressRepository {
  @override
  Future<Map<String, int>> loadAll({
    required String serverId,
    required String userId,
  }) {
    fail('The default resume list must not be modified by local progress');
  }
}

void main() {
  test('home preserves Jellyfin resume entries and server ordering', () async {
    final client = _Client();
    final container = ProviderContainer(
      overrides: [
        libraryViewsProvider.overrideWith(
          (ref) async =>
              LibraryData(client: client, userId: 'user', views: const []),
        ),
        playbackProgressRepositoryProvider.overrideWithValue(_Progress()),
      ],
    );
    addTearDown(container.dispose);
    final items = await container.read(resumeItemsProvider.future);
    expect(items, same(client.result));
    expect(items.map((item) => item.id), ['episode-4', 'episode-5', 'movie']);
    expect(client.calls, 1);
  });

  test(
    'refresh fetches updated native resume list including an empty result',
    () async {
      final client = _Client();
      final container = ProviderContainer(
        overrides: [
          libraryViewsProvider.overrideWith(
            (ref) async =>
                LibraryData(client: client, userId: 'user', views: const []),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(resumeItemsProvider.future);
      client.result = [];
      container.invalidate(resumeItemsProvider);
      expect(await container.read(resumeItemsProvider.future), isEmpty);
      expect(client.calls, 2);
    },
  );
}
