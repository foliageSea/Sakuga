import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/app/shell.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/media_server_factory.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/detail/detail_page.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_page.dart';
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
  _Client(ServerProfile server, {this.paginated = true})
    : super(server: server);

  final bool paginated;

  String get itemName => server.name;

  MediaItem get libraryItem =>
      MediaItem(id: 'same-item-id', name: itemName, type: MediaType.movie);

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
      items: [libraryItem],
      totalRecordCount: paginated ? 2 : 1,
    );
  }
}

const _a = ServerProfile(id: 'a', name: 'Server A', baseUrl: 'https://a.test');
const _b = ServerProfile(id: 'b', name: 'Server B', baseUrl: 'https://b.test');

class _WidgetClient extends _Client {
  _WidgetClient(super.server) : super(paginated: false);

  final searchTerms = <String>[];

  @override
  String get itemName => '${server.name} feature';

  @override
  Future<List<MediaLibrary>> views(String userId) async => [
    // Both servers expose the same IDs so a stale selection would still match.
    MediaLibrary(
      id: 'first',
      name: '${server.name} Movies',
      type: MediaLibraryType.movies,
    ),
    MediaLibrary(
      id: 'second',
      name: '${server.name} Shows',
      type: MediaLibraryType.tvShows,
    ),
  ];

  @override
  Future<List<String>> genres(String userId, String parentId) async => [
    'Drama',
  ];

  @override
  Future<List<int>> years(String userId, String parentId) async => [2025];

  @override
  Future<List<MediaItem>> search(
    String userId,
    String term, {
    int limit = 60,
  }) async {
    searchTerms.add(term);
    return [
      MediaItem(
        id: 'search-hit',
        name: '${server.name} search hit',
        type: MediaType.movie,
      ),
    ];
  }
}

class _SeriesClient extends _WidgetClient {
  _SeriesClient(super.server);

  @override
  MediaItem get libraryItem =>
      MediaItem(id: 'same-item-id', name: itemName, type: MediaType.series);

  @override
  Future<MediaItem> item(String userId, String itemId) async => libraryItem;

  @override
  Future<List<MediaItem>> seasons(String userId, String seriesId) async => [];

  @override
  Future<List<MediaItem>> episodes(
    String userId,
    String seriesId, {
    String? seasonId,
  }) async => [];
}

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester,
  MemoryServerRepository repository,
  Map<String, _WidgetClient> clients, {
  double width = 1280,
  bool fullScreen = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      initialSettingsProvider.overrideWithValue(
        const AppSettings(language: 'en'),
      ),
      settingsRepositoryProvider.overrideWithValue(MemorySettings()),
      desktopWindowProvider.overrideWithValue(
        FakeWindow(available: width >= 600, macOS: true)
          ..fullScreen = fullScreen,
      ),
      serverRepositoryProvider.overrideWithValue(repository),
      mediaServerClientProvider.overrideWith(
        (ref, server) => clients[server.id]!,
      ),
      playbackProgressRepositoryProvider.overrideWithValue(_Progress()),
      randomItemsProvider.overrideWith((ref) async => const []),
      resumeItemsProvider.overrideWith((ref) async => const []),
      latestItemsProvider.overrideWith((ref) async => const []),
    ],
  );
  addTearDown(container.dispose);
  container.read(routerProvider).go('/library');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SakugaApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<Finder> _openPicker(WidgetTester tester) async {
  await tester.tap(_key('library-server-switch'));
  await tester.pumpAndSettle();
  final dialog = _key('library-server-switch-dialog');
  expect(tester.widget(dialog), isA<FDialog>());
  expect(
    Navigator.of(tester.element(dialog)),
    same(rootNavigatorKey.currentState),
  );
  return dialog;
}

Finder _option(Finder dialog, ServerProfile server) => find.descendant(
  of: dialog,
  matching: _key('library-server-option-${server.id}'),
);

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('switching servers exits series details at width $width', (
      tester,
    ) async {
      final repository = MemoryServerRepository()..items = [_a, _b];
      final container = await _pumpLibrary(tester, repository, {
        'a': _SeriesClient(_a),
        'b': _SeriesClient(_b),
      }, width: width);
      final router = container.read(routerProvider);
      final cardLayout = width < 600 ? 'mobile' : 'desktop';
      await tester.tap(_key('library-$cardLayout-card-same-item-id'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/library/same-item-id');
      expect(find.byType(DetailPage), findsOneWidget);

      var dialog = await _openPicker(tester);
      await tester.tap(_option(dialog, _a));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/library/same-item-id');

      repository.fail = true;
      dialog = await _openPicker(tester);
      await tester.tap(_option(dialog, _b));
      await tester.pumpAndSettle();
      expect(container.read(activeServerProvider), _a);
      expect(router.state.uri.path, '/library/same-item-id');

      // Let the error toast clear the mobile header before retrying.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      repository.fail = false;
      dialog = await _openPicker(tester);
      await tester.tap(_option(dialog, _b));
      await tester.pumpAndSettle();
      expect(container.read(activeServerProvider), _b);
      expect(router.state.uri.path, '/library');
      expect(find.byType(DetailPage), findsNothing);
      expect(find.text('Server B feature'), findsOneWidget);
    });

    testWidgets(
      'approved library switch resets browsing state at width $width',
      (tester) async {
        final repository = MemoryServerRepository()..items = [_a, _b];
        final a = _WidgetClient(_a);
        final b = _WidgetClient(_b);
        final container = await _pumpLibrary(tester, repository, {
          'a': a,
          'b': b,
        }, width: width);
        final router = container.read(routerProvider);
        final page = tester.element(find.byType(LibraryPage));
        final switchButton = _key('library-server-switch');
        expect(switchButton, findsOneWidget);
        expect(
          find.ancestor(
            of: switchButton,
            matching: width >= 600
                ? find.byType(DesktopTitleBar)
                : _key('mobile-header'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: switchButton,
            matching: find.byIcon(FLucideIcons.arrowRightLeft),
          ),
          findsNothing,
        );
        final search = _key('library-search');
        final filters = _key('library-toggle-filters');

        await tester.tap(find.text('Server A Shows'));
        await tester.pumpAndSettle();
        for (final key in [
          'library-toggle-filters',
          'library-genre-Drama',
          'library-progress-false',
          'library-year-2025',
        ]) {
          await tester.tap(_key(key));
          await tester.pumpAndSettle();
        }
        expect(
          a.queries.last,
          const LibraryQuery(
            userId: 'user-1',
            viewId: 'second',
            genre: 'Drama',
            isPlayed: false,
            year: 2025,
          ),
        );
        expect(
          _key(
            'library-${width < 600 ? 'mobile' : 'desktop'}-card-same-item-id',
          ),
          findsOneWidget,
        );
        expect(_key('library-clear-filters'), findsOneWidget);

        await tester.enterText(search, 'old query');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(a.searchTerms, ['old query']);
        expect(find.text('Server A search hit'), findsOneWidget);

        var dialog = await _openPicker(tester);
        expect(tester.widget<FButton>(_option(dialog, _a)).selected, isTrue);
        expect(tester.widget<FButton>(_option(dialog, _b)).selected, isFalse);
        expect(container.read(activeServerProvider), _a);
        expect(repository.items, [_a, _b]);
        // Dismiss the root dialog without choosing: browsing state must survive.
        rootNavigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(repository.items, [_a, _b]);
        expect(find.text('Server A search hit'), findsOneWidget);

        dialog = await _openPicker(tester);
        await tester.tap(_option(dialog, _b));
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(container.read(activeServerProvider), _b);
        expect(repository.items, [_b, _a]);
        expect(router.routeInformationProvider.value.uri.path, '/library');
        expect(tester.element(find.byType(LibraryPage)), same(page));
        expect(
          b.queries.last,
          const LibraryQuery(userId: 'user-1', viewId: 'first'),
        );
        expect(find.text('Server A search hit'), findsNothing);
        expect(find.text('Server B feature'), findsOneWidget);
        expect(
          _key(
            'library-${width < 600 ? 'mobile' : 'desktop'}-card-same-item-id',
          ),
          findsOneWidget,
        );
        expect(_key('library-clear-filters'), findsNothing);

        if (search.evaluate().isEmpty) {
          await tester.tap(filters);
          await tester.pumpAndSettle();
        }
        final input = find.descendant(
          of: search,
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(input).controller.text, isEmpty);
        expect(
          b.searchTerms,
          isEmpty,
          reason: 'The old search must not run on the new server.',
        );
      },
    );
  }

  testWidgets(
    'failed library switch keeps the original server and shows the error',
    (tester) async {
      final repository = MemoryServerRepository()
        ..items = [_a, _b]
        ..fail = true;
      final a = _WidgetClient(_a);
      final b = _WidgetClient(_b);
      final container = await _pumpLibrary(tester, repository, {
        'a': a,
        'b': b,
      });
      final router = container.read(routerProvider);
      await tester.tap(find.text('Server A Shows'));
      await tester.pumpAndSettle();

      final dialog = await _openPicker(tester);
      await tester.tap(_option(dialog, _b));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/library');
      expect(container.read(activeServerProvider), _a);
      expect(repository.items, [_a, _b]);
      expect(a.queries.last.viewId, 'second');
      expect(b.queries, isEmpty);
      expect(find.text('Server A feature'), findsOneWidget);
      expect(find.text('Server B feature'), findsNothing);
      expect(
        find.textContaining('Could not save or read local data.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('desktop full screen falls back to a single page action', (
    tester,
  ) async {
    final repository = MemoryServerRepository()..items = [_a, _b];
    await _pumpLibrary(tester, repository, {
      'a': _WidgetClient(_a),
      'b': _WidgetClient(_b),
    }, fullScreen: true);
    expect(find.byType(DesktopTitleBar), findsNothing);
    final button = _key('library-server-switch');
    expect(button, findsOneWidget);
    expect(
      find.ancestor(of: button, matching: find.byType(LibraryPage)),
      findsOneWidget,
    );
    await _openPicker(tester);
  });

  testWidgets('single server action stays visible on home and settings', (
    tester,
  ) async {
    final repository = MemoryServerRepository()..items = [_a];
    final container = await _pumpLibrary(tester, repository, {
      'a': _WidgetClient(_a),
    }, width: 390);
    final router = container.read(routerProvider);
    for (final route in ['/library', '/home', '/settings']) {
      router.go(route);
      await tester.pumpAndSettle();
      final button = _key('library-server-switch');
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.text(_a.name)),
        findsOneWidget,
      );
      final dialog = await _openPicker(tester);
      expect(tester.widget<FButton>(_option(dialog, _a)).selected, isTrue);
      await tester.tap(_option(dialog, _a));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(repository.items, [_a]);
    }
  });

  testWidgets('empty server action stays visible but disabled', (tester) async {
    await _pumpLibrary(tester, MemoryServerRepository(), {}, width: 390);
    final button = _key('library-server-switch');
    expect(button, findsOneWidget);
    expect(tester.widget<FButton>(button).onPress, isNull);
    expect(
      find.descendant(of: button, matching: find.text('No servers')),
      findsOneWidget,
    );
  });

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
