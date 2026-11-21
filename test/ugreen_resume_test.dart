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

  late List<MediaItem> remote = [
    for (final id in ['both', 'completed', 'remote'])
      MediaItem(
        id: id,
        name: id,
        type: MediaType.movie,
        playbackPosition: const Duration(seconds: 21),
      ),
  ];

  @override
  Future<List<MediaItem>> resume(String userId, {int limit = 12}) async =>
      remote;

  @override
  Future<MediaItem> item(String userId, String itemId) async =>
      MediaItem(id: itemId, name: itemId, type: MediaType.movie);
}

class _Progress extends Fake implements PlaybackProgressRepository {
  Map<String, SavedPlaybackProgress> entries = {};

  @override
  Future<Map<String, SavedPlaybackProgress>> loadAllEntries({
    required String serverId,
    required String userId,
  }) async => entries;
}

void main() {
  test(
    'refresh keeps a stable order when NAS and local ordering change',
    () async {
      final tiedDate = DateTime.utc(2026, 1, 2);
      final repository = _Progress()
        ..entries = {
          'local-legacy': (positionTicks: 70000000, lastPlayedAt: null),
          'local-recent': (
            positionTicks: 90000000,
            lastPlayedAt: DateTime.utc(2026, 1, 3),
          ),
          'local-tied': (positionTicks: 80000000, lastPlayedAt: tiedDate),
        };
      final client = _Client()
        ..remote = [
          const MediaItem(
            id: 'remote-undated',
            name: '',
            type: MediaType.movie,
          ),
          MediaItem(
            id: 'nas-tied',
            name: '',
            type: MediaType.movie,
            lastPlayedAt: tiedDate,
          ),
          MediaItem(
            id: 'nas-latest',
            name: '',
            type: MediaType.movie,
            lastPlayedAt: DateTime.utc(2026, 1, 4),
          ),
        ];
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
      Future<List<String>> order() async => [
        for (final item in await container.read(resumeItemsProvider.future))
          item.id,
      ];
      const expected = [
        'nas-latest',
        'local-recent',
        'local-tied',
        'nas-tied',
        'local-legacy',
        'remote-undated',
      ];
      expect(await order(), expected);

      client.remote = client.remote.reversed.toList();
      repository.entries = Map.fromEntries(
        repository.entries.entries.toList().reversed,
      );
      container.invalidate(resumeItemsProvider);
      expect(await order(), expected);

      repository.entries['local-legacy'] = (
        positionTicks: 71000000,
        lastPlayedAt: DateTime.utc(2026, 1, 5),
      );
      container.invalidate(resumeItemsProvider);
      expect(await order(), [
        'local-legacy',
        ...expected.where((id) => id != 'local-legacy'),
      ]);
    },
  );
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
