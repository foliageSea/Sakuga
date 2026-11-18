import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

class _Client extends FakeMediaServerClient {
  _Client()
    : super(
        server: const ServerProfile(
          id: 'nas',
          name: 'NAS',
          baseUrl: 'https://nas.local:9443',
          type: MediaServerType.ugreen,
        ),
      );

  @override
  Future<List<MediaItem>> resume(String userId, {int limit = 12}) async => [
    for (final id in ['both', 'completed', 'remote'])
      MediaItem(
        id: id,
        name: id,
        type: MediaType.movie,
        playbackPosition: const Duration(seconds: 21),
      ),
  ];

  @override
  Future<MediaItem> item(String userId, String itemId) async =>
      MediaItem(id: itemId, name: itemId, type: MediaType.movie);
}

void main() {
  test(
    'UGREEN resumes local items, deduplicates and hides completed items',
    () async {
      final previous = SharedPreferencesAsyncPlatform.instance;
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final repository = PreferencesPlaybackProgressRepository(
        SharedPreferencesAsync(),
      );
      for (final entry in {
        'local': 70000000,
        'both': 90000000,
        'completed': 0,
      }.entries) {
        await repository.save(
          serverId: 'nas',
          userId: 'user',
          itemId: entry.key,
          positionTicks: entry.value,
        );
      }
      await repository.save(
        serverId: 'nas',
        userId: 'other-user',
        itemId: 'unrelated',
        positionTicks: 20000000,
      );
      final client = _Client();
      final container = ProviderContainer.test(
        overrides: [
          playbackProgressRepositoryProvider.overrideWithValue(repository),
          libraryViewsProvider.overrideWith(
            (ref) async =>
                LibraryData(client: client, userId: 'user', views: const []),
          ),
        ],
      );
      container.listen(resumeItemsProvider, (_, _) {});
      final items = await container.read(resumeItemsProvider.future);
      expect(
        {for (final item in items) item.id: item.playbackPosition?.inSeconds},
        {'local': 7, 'both': 9, 'remote': 21},
      );
      expect(items, hasLength(3));
    },
  );
}
