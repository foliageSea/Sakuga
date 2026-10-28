import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
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

const _server = ServerProfile(
  id: 'jellyfin',
  name: 'Jellyfin',
  baseUrl: 'https://media.test',
  apiKey: 'test-key',
);

MediaServerClient _browseClient(_BrowseAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: _server.baseUrl))
    ..httpClientAdapter = adapter;
  addTearDown(dio.close);
  return JellyfinClient(server: _server, dio: dio);
}

class _BrowseAdapter implements HttpClientAdapter {
  _BrowseAdapter(this.response);

  final Map<String, dynamic> response;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'genres requests the recursive library scope and returns every name',
    () async {
      final names = [
        '科幻 & Fantasy',
        ...List.generate(75, (index) => 'Genre $index'),
      ];
      final adapter = _BrowseAdapter({
        'Items': [
          for (final name in names) {'Name': name},
          {'Id': 'missing-name'},
          {'Name': null},
        ],
        'TotalRecordCount': names.length,
      });
      final client = _browseClient(adapter);

      expect(await client.genres('user-1', 'library-1'), names);
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/Genres');
      expect(request.queryParameters, {
        'UserId': 'user-1',
        'ParentId': 'library-1',
        'Recursive': true,
        'IncludeItemTypes': 'Movie,Series,Episode,Video,MusicVideo',
      });
      expect(request.uri.queryParameters.containsKey('Limit'), isFalse);
    },
  );

  test('genres returns an empty list when the library has no genres', () async {
    for (final response in <Map<String, dynamic>>[
      {'Items': [], 'TotalRecordCount': 0},
      {},
    ]) {
      final client = _browseClient(_BrowseAdapter(response));
      expect(await client.genres('user-1', 'library-1'), isEmpty);
    }
  });

  test(
    'years requests library filters and normalizes positive integers',
    () async {
      final adapter = _BrowseAdapter({
        'Years': [2020, 1998, 2025, 2020, 0, -1, null, '2024', 2023.5, true],
      });
      final client = _browseClient(adapter);

      expect(await client.years('user-1', 'library-1'), [2025, 2020, 1998]);
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/Items/Filters');
      expect(request.queryParameters, {
        'userId': 'user-1',
        'parentId': 'library-1',
        'includeItemTypes': 'Movie,Series,Video,MusicVideo',
      });
    },
  );

  test('years returns an empty list for absent or unusable years', () async {
    for (final response in <Map<String, dynamic>>[
      {},
      {'Years': null},
      {'Years': []},
      {
        'Years': [0, -2020, null, 'unknown', 2020.5],
      },
    ]) {
      final client = _browseClient(_BrowseAdapter(response));
      expect(await client.years('user-1', 'library-1'), isEmpty);
    }
  });

  test(
    'items combines genre, year and played filters with paging and sorting',
    () async {
      final adapter = _BrowseAdapter({
        'Items': [
          {'Id': 'series-1', 'Name': 'A show', 'Type': 'Series'},
        ],
        'TotalRecordCount': 42,
      });
      final client = _browseClient(adapter);
      const genre = '科幻 & Fantasy';

      final page = await client.items(
        'user-1',
        'library-1',
        startIndex: 30,
        limit: 30,
        types: {MediaType.series},
        sort: MediaSort.random,
        genre: genre,
        isPlayed: false,
        year: 2024,
        descending: true,
      );

      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/Items');
      expect(request.uri.queryParameters['Genres'], genre);
      expect(request.queryParameters, containsPair('userId', 'user-1'));
      expect(request.queryParameters, containsPair('parentId', 'library-1'));
      expect(request.queryParameters, containsPair('recursive', true));
      expect(
        request.queryParameters,
        containsPair('includeItemTypes', 'Series'),
      );
      expect(request.queryParameters, containsPair('isPlayed', false));
      expect(request.queryParameters, containsPair('years', 2024));
      expect(request.uri.queryParameters['isPlayed'], 'false');
      expect(request.uri.queryParameters['years'], '2024');
      expect(request.queryParameters, containsPair('sortBy', 'Random'));
      expect(request.queryParameters, containsPair('sortOrder', 'Descending'));
      expect(request.queryParameters, containsPair('startIndex', 30));
      expect(request.queryParameters, containsPair('limit', 30));
      expect(page.items.single.id, 'series-1');
      expect(page.items.single.type, MediaType.series);
      expect(page.totalRecordCount, 42);
    },
  );

  test(
    'items omits unset filters and defaults to ascending name order',
    () async {
      final adapter = _BrowseAdapter({'Items': [], 'TotalRecordCount': 0});
      final client = _browseClient(adapter);

      await client.items('user-1', 'library-1');
      await client.items('user-1', 'library-1', genre: '');

      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(request.uri.queryParameters.containsKey('Genres'), isFalse);
        expect(request.uri.queryParameters.containsKey('isPlayed'), isFalse);
        expect(request.uri.queryParameters.containsKey('years'), isFalse);
        expect(request.queryParameters, containsPair('sortBy', 'SortName'));
        expect(request.queryParameters, containsPair('sortOrder', 'Ascending'));
        expect(request.queryParameters, containsPair('startIndex', 0));
        expect(request.queryParameters, containsPair('limit', 60));
      }
    },
  );

  test('items sends the played filter when selecting watched media', () async {
    final adapter = _BrowseAdapter({'Items': [], 'TotalRecordCount': 0});
    final client = _browseClient(adapter);

    await client.items('user-1', 'library-1', isPlayed: true);

    final request = adapter.requests.single;
    expect(request.queryParameters, containsPair('isPlayed', true));
    expect(request.uri.queryParameters['isPlayed'], 'true');
    expect(request.queryParameters.containsKey('years'), isFalse);
  });

  for (final (sort, field) in [
    (MediaSort.name, 'SortName'),
    (MediaSort.random, 'Random'),
    (MediaSort.dateAdded, 'DateCreated'),
    (MediaSort.year, 'ProductionYear'),
    (MediaSort.rating, 'CommunityRating'),
  ]) {
    for (final descending in [false, true]) {
      test('items maps $sort with descending=$descending', () async {
        final adapter = _BrowseAdapter({'Items': [], 'TotalRecordCount': 0});
        final client = _browseClient(adapter);

        await client.items(
          'user-1',
          'library-1',
          sort: sort,
          descending: descending,
        );

        final request = adapter.requests.single;
        expect(request.queryParameters, containsPair('sortBy', field));
        expect(
          request.queryParameters,
          containsPair('sortOrder', descending ? 'Descending' : 'Ascending'),
        );
      });
    }
  }

  test(
    'seasons requests one series and maps season numbers and counts',
    () async {
      final adapter = _BrowseAdapter({
        'Items': [
          for (final number in [2, 0, 1])
            {
              'Id': 'season-$number',
              'Name': 'Season $number',
              'Type': 'Season',
              'IndexNumber': number,
              'SeriesId': 'series-1',
              'SeriesName': 'A show',
              'ChildCount': number == 0 ? 2 : 12,
              'RecursiveItemCount': number == 0 ? 2 : 12,
              'CommunityRating': 8.5,
            },
        ],
        'TotalRecordCount': 3,
      });
      final client = _browseClient(adapter);

      final seasons = await client.seasons('user-1', 'series-1');

      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/Shows/series-1/Seasons');
      expect(request.queryParameters, {
        'userId': 'user-1',
        'fields': request.queryParameters['fields'],
        'enableImageTypes': 'Primary,Backdrop,Logo',
        'imageTypeLimit': 1,
      });
      expect(
        (request.queryParameters['fields'] as String).split(','),
        unorderedEquals([
          'RunTimeTicks',
          'PrimaryImageAspectRatio',
          'ImageTags',
          'UserData',
          'ChildCount',
          'RecursiveItemCount',
        ]),
      );
      expect(seasons.map((season) => season.id), [
        'season-0',
        'season-1',
        'season-2',
      ]);
      expect(seasons.map((season) => season.indexNumber), [0, 1, 2]);
      expect(seasons.map((season) => season.childCount), [2, 12, 12]);
      expect(seasons.map((season) => season.recursiveItemCount), [2, 12, 12]);
      for (final season in seasons) {
        expect(season.type, MediaType.season);
        expect(season.seriesId, 'series-1');
        expect(season.seriesName, 'A show');
        expect(season.communityRating, 8.5);
      }
    },
  );

  for (final seasonId in <String?>[null, 'season-1']) {
    test(
      'episodes requests overview and sorts metadata with seasonId=$seasonId',
      () async {
        final adapter = _BrowseAdapter({
          'Items': [
            for (final (season, episode) in [(2, 1), (1, 10), (0, 1), (1, 2)])
              if (seasonId == null || seasonId == 'season-$season')
                {
                  'Id': 'episode-$season-$episode',
                  'Name': 'Episode $episode',
                  'Type': 'Episode',
                  'SeriesId': 'series-1',
                  'SeriesName': 'A show',
                  'SeasonId': 'season-$season',
                  'IndexNumber': episode,
                  'ParentIndexNumber': season,
                  'Overview': 'Overview for episode $season-$episode',
                  'RunTimeTicks': 14401234560,
                  'CommunityRating': 9,
                  'UserData': {
                    'PlaybackPositionTicks': 600000000,
                    'Played': false,
                  },
                },
          ],
        });
        final client = _browseClient(adapter);

        final episodes = await client.episodes(
          'user-1',
          'series-1',
          seasonId: seasonId,
        );

        final request = adapter.requests.single;
        expect(request.method, 'GET');
        expect(request.path, '/Shows/series-1/Episodes');
        expect(request.queryParameters, {
          'userId': 'user-1',
          'seasonId': ?seasonId,
          'fields': request.queryParameters['fields'],
          'enableImageTypes': 'Primary,Backdrop,Logo',
          'imageTypeLimit': 1,
        });
        expect(request.uri.queryParameters['seasonId'], seasonId);
        expect(
          (request.queryParameters['fields'] as String).split(','),
          unorderedEquals([
            'RunTimeTicks',
            'PrimaryImageAspectRatio',
            'ImageTags',
            'UserData',
            'ChildCount',
            'RecursiveItemCount',
            'Overview',
          ]),
        );
        expect(
          episodes.map((episode) => episode.episodeCode),
          seasonId == null
              ? ['S00E01', 'S01E02', 'S01E10', 'S02E01']
              : ['S01E02', 'S01E10'],
        );
        final episode = episodes.firstWhere((item) => item.id == 'episode-1-2');
        expect(episode.type, MediaType.episode);
        expect(episode.name, 'Episode 2');
        expect(episode.seriesId, 'series-1');
        expect(episode.seriesName, 'A show');
        expect(episode.seasonId, 'season-1');
        expect(episode.indexNumber, 2);
        expect(episode.parentIndexNumber, 1);
        expect(episode.overview, 'Overview for episode 1-2');
        expect(episode.runtime, const Duration(microseconds: 1440123456));
        expect(episode.communityRating, 9.0);
        expect(episode.playbackPosition, const Duration(minutes: 1));
        expect(episode.played, isFalse);
      },
    );
  }

  test('fake clients provide empty genre and year lists by default', () async {
    final MediaServerClient client = FakeMediaServerClient(server: _server);
    expect(await client.genres('user-1', 'library-1'), isEmpty);
    expect(await client.years('user-1', 'library-1'), isEmpty);
  });

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
