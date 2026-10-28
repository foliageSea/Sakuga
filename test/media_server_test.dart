import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sakuga/data/jellyfin/jellyfin_mapper.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/media_server_client.dart';
import 'package:sakuga/data/media_server/media_server_factory.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/library/library_providers.dart';

import 'fakes.dart';

class _Factory extends MediaServerFactory {
  final profiles = <ServerProfile>[];
  @override
  MediaServerClient createClient(ServerProfile server) {
    profiles.add(server);
    return FakeMediaServerClient(server: server);
  }
}

void main() {
  test(
    'reads legacy profiles and persists type without changing storage keys',
    () async {
      final original = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
      final preferences = SharedPreferencesAsync();
      await preferences.setString(
        'sakuga.servers.v1',
        jsonEncode([
          {
            'id': 'legacy',
            'name': 'Old server',
            'baseUrl': 'https://media.test',
            'apiKey': 'key',
          },
        ]),
      );
      final repository = PreferencesServerRepository(preferences);
      final profiles = await repository.load();
      expect(profiles.single.type, MediaServerType.jellyfin);
      await repository.save([profiles.single.copyWith(name: 'Renamed')]);
      final reopened = (await repository.load()).single;
      expect(reopened.id, 'legacy');
      expect(reopened.apiKey, 'key');
      expect(reopened.name, 'Renamed');
      expect(reopened.toJson()['type'], 'jellyfin');
      expect(
        () => ServerProfile.fromJson({'type': 'unrecognized'}),
        throwsArgumentError,
      );
    },
  );

  test('maps metadata, progress and authenticated image fallback at the adapter boundary', () {
    const mapper = JellyfinMapper(
      baseUrl: 'https://media.test/jellyfin/',
      headers: {'Authorization': 'test'},
    );
    final item = mapper.item({
      'Id': 'episode',
      'Name': 'Pilot',
      'Type': 'Episode',
      'SeriesId': 'series',
      'SeriesName': 'Show',
      'IndexNumber': 3,
      'ParentIndexNumber': 1,
      'ParentPrimaryImageItemId': 'season',
      'ParentPrimaryImageTag': 'season-tag',
      'SeriesPrimaryImageTag': 'series-tag',
      'BackdropImageTags': ['backdrop-tag'],
      'RunTimeTicks': 600000000,
      'UserData': {'PlaybackPositionTicks': 150000000, 'Played': false},
    });
    expect(item.type, MediaType.episode);
    expect(item.runtime, const Duration(seconds: 60));
    expect(item.playbackPosition, const Duration(seconds: 15));
    expect(item.progressFraction, 0.25);
    expect(item.episodeCode, 'S01E03');
    expect(
      item.poster!.url(),
      'https://media.test/jellyfin/Items/season/Images/Primary?maxWidth=600&tag=season-tag',
    );
    expect(item.poster!.headers, {'Authorization': 'test'});
    expect(
      item.backdrop!.url(width: 1920),
      contains('Backdrop/0?maxWidth=1920'),
    );
    final overlay = item.withPlaybackPosition(const Duration(seconds: 30));
    expect(overlay.progressFraction, 0.5);
    expect(overlay.poster, same(item.poster));
    expect(
      overlay.withPlaybackPosition(Duration.zero).progressFraction,
      isNull,
    );
    expect(mapper.item({'Type': 'FutureType'}).type, MediaType.unknown);
    expect(
      mapper.library({'CollectionType': 'tvshows'}).type,
      MediaLibraryType.tvShows,
    );
  });

  test(
    'maps transparent logos and preserves them through playback overlays',
    () {
      const mapper = JellyfinMapper(
        baseUrl: 'https://media.test/jellyfin/',
        headers: {'Authorization': 'test'},
      );
      final item = mapper.item({
        'Id': 'movie',
        'ImageTags': {'Logo': 'logo tag'},
        'ParentLogoItemId': 'series',
        'ParentLogoImageTag': 'parent-logo',
      });
      final logo = item.logo!;
      expect(
        logo.url(width: 900),
        'https://media.test/jellyfin/Items/movie/Images/Logo'
        '?maxWidth=900&tag=logo+tag&format=Png',
      );
      expect(logo.headers, {'Authorization': 'test'});
      expect(
        logo.cacheKey,
        'https://media.test/jellyfin/Items/movie/Images/Logo'
        '?tag=logo+tag&format=Png',
      );
      expect(
        item.withPlaybackPosition(const Duration(seconds: 30)).logo,
        same(logo),
      );
      expect(item.withPlaybackPosition(Duration.zero).logo, same(logo));
    },
  );

  test('uses parent logos and leaves missing artwork null', () {
    const mapper = JellyfinMapper(baseUrl: 'https://media.test', headers: {});
    final episode = mapper.item({
      'Id': 'episode',
      'ImageTags': {'Logo': ''},
      'ParentLogoItemId': 'series',
      'ParentLogoImageTag': 'parent-logo',
    });
    expect(
      episode.logo!.url(),
      'https://media.test/Items/series/Images/Logo'
      '?maxWidth=600&tag=parent-logo&format=Png',
    );
    for (final json in <Map<String, dynamic>>[
      {'Id': 'movie'},
      {
        'Id': 'movie',
        'ImageTags': {'Primary': 'poster'},
      },
      {
        'Id': 'movie',
        'ImageTags': {'Logo': ''},
      },
      {'Id': 'movie', 'ParentLogoItemId': 'series'},
      {
        'ImageTags': {'Logo': 'logo'},
      },
    ]) {
      expect(mapper.item(json).logo, isNull);
    }
  });

  test('library resolves a client from the factory and switches without Jellyfin inheritance', () async {
    const a = ServerProfile(id: 'a', name: 'A', baseUrl: 'https://a.test');
    const b = ServerProfile(id: 'b', name: 'B', baseUrl: 'https://b.test');
    final repository = MemoryServerRepository()..items = [a, b];
    final factory = _Factory();
    final container = ProviderContainer(
      overrides: [
        serverRepositoryProvider.overrideWithValue(repository),
        mediaServerFactoryProvider.overrideWithValue(factory),
      ],
    );
    addTearDown(container.dispose);
    await container.read(serversProvider.future);
    final subscription = container.listen(libraryViewsProvider, (_, _) {});
    addTearDown(subscription.close);
    final first = await container.read(libraryViewsProvider.future);
    expect(first.client, isA<FakeMediaServerClient>());
    expect(first.client.server.id, 'a');
    expect(first.userId, 'user-1');
    await container.read(serversProvider.notifier).setActive('b');
    await container.pump();
    final second = await container.read(libraryViewsProvider.future);
    expect(second.client.server.id, 'b');
    expect(factory.profiles.map((profile) => profile.id), ['a', 'b']);
  });
}
