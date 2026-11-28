import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp, TextField;
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/detail/detail_page.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_page.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/media_widgets.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

const _gridOverview =
    'A long synopsis that should fit in at most two lines instead of pushing surrounding media out of the list.';

MediaItem _item(String id, double ratio) => MediaItem(
  id: id,
  name: 'Series $id',
  type: MediaType.series,
  primaryImageAspectRatio: ratio,
  overview: id == 'a' ? _gridOverview : null,
  productionYear: id == 'd' ? null : 2023,
  communityRating: 8.4,
  recursiveItemCount: id == 'd' ? null : 12,
  runtime: id == 'a' ? const Duration(minutes: 24) : null,
  playbackPosition: id == 'a' ? const Duration(minutes: 6) : null,
);

class _FakeItems extends LibraryItemsController {
  _FakeItems(super.query, {this.items});

  final List<MediaItem>? items;

  @override
  Future<LibraryItemsState> build() async {
    final items =
        this.items ??
        [_item('a', 0.5), _item('b', 1.2), _item('c', 0.7), _item('d', 0.7)];
    return LibraryItemsState(items: items, totalRecordCount: items.length);
  }
}

class _SearchClient extends FakeMediaServerClient {
  _SearchClient() : super(server: _server);

  final terms = <String>[];
  Future<List<MediaItem>> Function(String term)? searchItems;

  @override
  Future<List<MediaItem>> search(
    String userId,
    String term, {
    int limit = 60,
  }) async {
    expect(userId, 'user-1');
    terms.add(term);
    return searchItems?.call(term) ?? [_item('result', 0.7)];
  }
}

class _Progress extends Fake implements PlaybackProgressRepository {
  @override
  Future<Map<String, int>> loadAll({
    required String serverId,
    required String userId,
  }) async => {};
}

class _GenreClient extends FakeMediaServerClient {
  _GenreClient({super.server = _server});

  final requests = <({String viewId, String? genre, int startIndex})>[];
  bool failGenres = false;
  bool failYears = false;
  List<int> availableYears = [2026, 2025, 2023];
  final filters = <LibraryQuery>[];

  @override
  Future<List<int>> years(String userId, String parentId) async {
    if (failYears) throw const AppException(FailureKind.network);
    return availableYears;
  }

  @override
  Future<List<String>> genres(String userId, String parentId) async {
    if (failGenres) throw const AppException(FailureKind.network);
    return parentId == 'view' ? ['Animation', 'Drama'] : ['Comedy'];
  }

  @override
  Future<MediaItemsPage> items(
    String userId,
    String parentId, {
    int startIndex = 0,
    int limit = 60,
    Set<MediaType> types = const {},
    MediaSort sort = MediaSort.name,
    String? genre,
    bool? isPlayed,
    int? year,
    bool descending = false,
  }) async {
    requests.add((viewId: parentId, genre: genre, startIndex: startIndex));
    filters.add(
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
    return MediaItemsPage(
      items: [
        MediaItem(
          id: '$parentId-${genre ?? 'all'}-$startIndex',
          name: '${genre ?? 'All'} title $startIndex',
          type: MediaType.series,
        ),
      ],
      totalRecordCount: 1,
    );
  }
}

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester,
  Size size, {
  FakeMediaServerClient? client,
  bool useRealItems = false,
  bool expandFilters = false,
  List<MediaLibrary>? views,
  List<MediaItem>? items,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final servers = MemoryServerRepository()..items = [client?.server ?? _server];
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      serverRepositoryProvider.overrideWithValue(servers),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: client ?? FakeMediaServerClient(server: _server),
          userId: 'user-1',
          views:
              views ??
              const [
                MediaLibrary(
                  id: 'view',
                  name: 'Shows',
                  type: MediaLibraryType.tvShows,
                ),
              ],
        ),
      ),
      playbackProgressRepositoryProvider.overrideWithValue(_Progress()),
      if (!useRealItems)
        libraryItemsProvider.overrideWith2(
          (query) => _FakeItems(query, items: items),
        ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(language: 'en'),
            brightness: Brightness.light,
            touch: true,
          ),
          child: child!,
        ),
        home: const LibraryPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('library-filter-panel')), findsNothing);
  if (expandFilters) {
    await tester.tap(find.byKey(const ValueKey('library-toggle-filters')));
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  testWidgets('Ugreen offers genre filtering without advanced options', (
    tester,
  ) async {
    final client = _GenreClient(
      server: _server.copyWith(
        type: MediaServerType.ugreen,
        baseUrl: 'https://nas.test:9443',
        userId: 'user-1',
        accessToken: 'test-token',
      ),
    );
    await _pumpLibrary(
      tester,
      const Size(720, 900),
      client: client,
      useRealItems: true,
      expandFilters: true,
    );
    Finder key(String id) => find.byKey(ValueKey('library-$id'));
    expect(key('progress'), findsNothing);
    expect(key('year'), findsNothing);
    expect(key('sort'), findsNothing);
    await tester.tap(key('genre-Animation'));
    await tester.pumpAndSettle();
    expect(client.filters.last.genre, 'Animation');
    expect(find.text('Animation title 0'), findsOneWidget);
    await tester.tap(key('clear-filters'));
    await tester.pumpAndSettle();
    expect(client.filters.last.genre, isNull);
    expect(find.text('All title 0'), findsOneWidget);
  });

  testWidgets(
    'older selected year remains visible after collapsing year options',
    (tester) async {
      final client = _GenreClient()
        ..availableYears = [for (var year = 2026; year >= 2010; year--) year];
      await _pumpLibrary(
        tester,
        const Size(1280, 900),
        client: client,
        useRealItems: true,
        expandFilters: true,
      );
      expect(find.byKey(const ValueKey('library-year-2010')), findsNothing);
      await tester.tap(find.text('More years'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-year-2010')));
      await tester.pumpAndSettle();
      expect(client.filters.last.year, 2010);
      await tester.tap(find.text('Fewer years'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-year-2010')), findsOneWidget);
      expect(client.filters.last.year, 2010);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'library grid shows aligned posters and metadata without synopsis',
    (tester) async {
      await _pumpLibrary(tester, const Size(1280, 900));
      final a = tester.getRect(_posterFrameFinder('a'));
      final b = tester.getRect(_posterFrameFinder('b'));
      final title = find.text('Series a');
      final overview = find.text(_gridOverview);
      expect(find.byType(AnimatedScale), findsNWidgets(4));
      expect(a.width / a.height, closeTo(2 / 3, 0.01));
      expect(a.size, b.size);
      expect(a.top, b.top);
      expect(tester.getRect(title).top, greaterThan(a.bottom));
      expect(overview, findsNothing);
      expect(tester.widget<Text>(title).maxLines, 1);
      _expectDurationBadge(tester, '00:24:00', a);
      expect(find.text('8.4'), findsNWidgets(4));
      expect(find.text('2023 · 12 episodes'), findsNWidgets(3));
      expect(find.byType(MediaProgressBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 760), const Size(1280, 900)]) {
    testWidgets(
      'library combines filters and sorting in the grid at ${size.width}',
      (tester) async {
        final client = _GenreClient();
        await _pumpLibrary(
          tester,
          size,
          client: client,
          useRealItems: true,
          expandFilters: true,
        );
        expect(find.text('1 title'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('library-progress-false')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('library-genre-Animation')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('library-year-2025')));
        await tester.pumpAndSettle();
        expect(client.filters.last.genre, 'Animation');
        expect(client.filters.last.isPlayed, false);
        expect(client.filters.last.year, 2025);
        await tester.tap(find.byKey(const ValueKey('library-toggle-filters')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-filter-panel')),
          findsNothing,
        );
        expect(find.text('Animation title 0'), findsOneWidget);
        expect(find.byKey(const ValueKey('library-list-view')), findsNothing);
        expect(find.byKey(const ValueKey('library-grid-view')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('library-sort')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('library-sort-rating')));
        await tester.pumpAndSettle();
        expect(client.filters.last.sort, MediaSort.rating);
        expect(client.filters.last.descending, true);
        expect(client.filters.last.genre, 'Animation');
        expect(client.filters.last.isPlayed, false);
        expect(client.filters.last.year, 2025);
        await tester.tap(find.byKey(const ValueKey('library-clear-filters')));
        await tester.pumpAndSettle();
        expect(client.filters.last.genre, isNull);
        expect(client.filters.last.isPlayed, isNull);
        expect(client.filters.last.year, isNull);
        expect(client.filters.last.sort, MediaSort.rating);
        expect(find.text('All title 0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('year options can retry without losing the selected genre', (
    tester,
  ) async {
    final client = _GenreClient()..failYears = true;
    await _pumpLibrary(
      tester,
      const Size(390, 900),
      client: client,
      useRealItems: true,
      expandFilters: true,
    );
    await tester.tap(find.byKey(const ValueKey('library-genre-Drama')));
    await tester.pumpAndSettle();
    client.failYears = false;
    await tester.tap(find.byKey(const ValueKey('library-years-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-year-2026')), findsOneWidget);
    expect(find.text('Drama title 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching server resets the selected genre', (tester) async {
    final client = _GenreClient();
    final container = await _pumpLibrary(
      tester,
      const Size(390, 900),
      client: client,
      useRealItems: true,
      expandFilters: true,
    );
    await tester.tap(find.text('Animation').last);
    await tester.pumpAndSettle();
    expect(find.text('Animation title 0'), findsOneWidget);
    await container
        .read(serversProvider.notifier)
        .add(
          const ServerProfile(
            id: 'other',
            name: 'Other server',
            baseUrl: 'https://other.test',
            apiKey: 'key',
          ),
        );
    await container.read(serversProvider.notifier).setActive('other');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-genre-all')), findsOneWidget);
    expect(find.text('All title 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 900), const Size(1280, 900)]) {
    testWidgets(
      'genre filter selects, clears and resets on view switch at ${size.width}',
      (tester) async {
        final client = _GenreClient();
        await _pumpLibrary(
          tester,
          size,
          client: client,
          useRealItems: true,
          expandFilters: true,
          views: const [
            MediaLibrary(
              id: 'view',
              name: 'Shows',
              type: MediaLibraryType.tvShows,
            ),
            MediaLibrary(
              id: 'movies',
              name: 'Movies',
              type: MediaLibraryType.movies,
            ),
          ],
        );
        expect(find.text('All title 0'), findsOneWidget);
        await tester.tap(find.text('Animation').last);
        await tester.pumpAndSettle();
        expect(client.requests.last, (
          viewId: 'view',
          genre: 'Animation',
          startIndex: 0,
        ));
        expect(find.text('Animation title 0'), findsOneWidget);
        expect(find.text('All title 0'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('library-genre-all')));
        await tester.pumpAndSettle();
        expect(find.text('All title 0'), findsOneWidget);

        await tester.tap(find.text('Drama').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Movies'));
        await tester.pumpAndSettle();
        expect(client.requests.last, (
          viewId: 'movies',
          genre: null,
          startIndex: 0,
        ));
        expect(find.byKey(const ValueKey('library-genre-all')), findsOneWidget);
        expect(find.text('Comedy'), findsOneWidget);
        expect(find.text('Animation'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('genre loading failure keeps library usable and can retry', (
    tester,
  ) async {
    final client = _GenreClient()..failGenres = true;
    await _pumpLibrary(
      tester,
      const Size(390, 900),
      client: client,
      useRealItems: true,
      expandFilters: true,
    );
    expect(find.text('All title 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-genres-retry')), findsOneWidget);
    client.failGenres = false;
    await tester.tap(find.byKey(const ValueKey('library-genres-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Animation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 900), const Size(1280, 900)]) {
    testWidgets('library searches and clears at width ${size.width}', (
      tester,
    ) async {
      final client = _SearchClient();
      await _pumpLibrary(tester, size, client: client);
      final toggle = find.byKey(const ValueKey('library-toggle-filters'));
      expect(find.byKey(const ValueKey('library-search')), findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(toggle).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('library-search'))).dy,
        ),
      );
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('library-search'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('library-filter-panel')))
              .dy,
        ),
      );
      final search = find.byKey(const ValueKey('library-search'));

      await tester.enterText(search, 'res');
      await tester.pump(const Duration(milliseconds: 200));
      expect(client.terms, isEmpty);
      await tester.enterText(search, '  result  ');
      await tester.pump(const Duration(milliseconds: 299));
      expect(client.terms, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(client.terms, ['result']);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(find.text('Series result'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        '  result  ',
      );
      expect(client.terms, ['result']);
      expect(find.text('Series result'), findsOneWidget);
      expect(find.text('Series a'), findsNothing);
      expect(find.text('Shows'), findsNothing);
      expect(
        find.byKey(
          ValueKey(
            size.width < 600
                ? 'library-mobile-card-result'
                : 'library-desktop-card-result',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pumpAndSettle();

      expect(client.terms, ['result']);
      expect(find.text('Series result'), findsNothing);
      expect(find.text('Series a'), findsOneWidget);
      expect(find.text('Shows'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('library search field blends into the page background', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      const Size(1280, 900),
      client: _SearchClient(),
      expandFilters: true,
    );
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('library-search')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration?.fillColor, const Color(0x00000000));
  });

  testWidgets('library shows empty results and retries a failed search', (
    tester,
  ) async {
    final client = _SearchClient()
      ..searchItems = (_) async =>
          throw const AppException(FailureKind.network);
    await _pumpLibrary(
      tester,
      const Size(1280, 900),
      client: client,
      expandFilters: true,
    );
    final search = find.byKey(const ValueKey('library-search'));

    await tester.enterText(search, 'missing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(client.terms, ['missing']);
    expect(find.text('Try again'), findsOneWidget);

    client.searchItems = (_) async => [];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(client.terms, ['missing', 'missing']);
    expect(find.text('No matching results'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late search results do not replace a newer query', (
    tester,
  ) async {
    final first = Completer<List<MediaItem>>();
    final client = _SearchClient()
      ..searchItems = (term) async =>
          term == 'first' ? first.future : [_item('second', 0.7)];
    await _pumpLibrary(
      tester,
      const Size(1280, 900),
      client: client,
      expandFilters: true,
    );
    final search = find.byKey(const ValueKey('library-search'));

    await tester.enterText(search, 'first');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(client.terms, ['first']);

    await tester.enterText(search, 'second');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Series second'), findsOneWidget);

    first.complete([_item('first', 0.7)]);
    await tester.pumpAndSettle();
    expect(find.text('Series first'), findsNothing);
    expect(find.text('Series second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from a search result preserves the library query', (
    tester,
  ) async {
    await _pumpRoutedLibrary(
      tester,
      size: const Size(1280, 900),
      client: _SearchClient(),
      loadItem: (id) async => _item(id, 0.7),
    );
    await tester.tap(find.byKey(const ValueKey('library-toggle-filters')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('library-search')),
      'result',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Series result'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-back')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail-back')));
    await tester.pumpAndSettle();
    expect(find.text('Series result'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'result',
    );
    expect(find.text('Shows'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile library aligns landscape thumbnails in two columns', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(390, 900));

    final first = tester.getTopLeft(
      find.byKey(const ValueKey('library-mobile-card-a')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('library-mobile-card-b')),
    );
    final third = tester.getTopLeft(
      find.byKey(const ValueKey('library-mobile-card-c')),
    );

    expect(second.dx, greaterThan(first.dx));
    expect(second.dy, first.dy);
    expect(third.dx, first.dx);
    expect(third.dy, greaterThan(second.dy));
    expect(
      tester.getSize(_posterFrameFinder('a')),
      tester.getSize(_posterFrameFinder('b')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop library keeps the aligned grid', (tester) async {
    await _pumpLibrary(tester, const Size(1280, 900));

    final headingRect = tester.getRect(find.text('Library'));
    final refreshButton = find.ancestor(
      of: find.byIcon(FLucideIcons.refreshCw),
      matching: find.byType(FButton),
    );
    final refreshRect = tester.getRect(refreshButton);
    final fourthCardRect = tester.getRect(
      find.byKey(const ValueKey('library-desktop-card-d')),
    );

    expect(refreshRect.center.dy, closeTo(headingRect.center.dy, 1.0));
    expect(refreshRect.right, greaterThan(fourthCardRect.right));
    final firstCardRect = tester.getRect(
      find.byKey(const ValueKey('library-desktop-card-a')),
    );
    expect(firstCardRect.top, fourthCardRect.top);
    expect(firstCardRect.width, closeTo(fourthCardRect.width, 0.01));
    expect(
      tester.getSize(_posterFrameFinder('a')),
      tester.getSize(_posterFrameFinder('d')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library scrolls inside the grid while keeping heading and view chips pinned',
    (tester) async {
      await _pumpLibrary(tester, const Size(1000, 560), items: _scrollItems());

      final headingFinder = find.text('Library');
      final viewChipFinder = find.text('Shows');
      final refreshButton = find.ancestor(
        of: find.byIcon(FLucideIcons.refreshCw),
        matching: find.byType(FButton),
      );
      final firstCard = find.byKey(const ValueKey('library-desktop-card-a'));
      final scrollView = find.byType(CustomScrollView);

      final headingTopLeft = tester.getTopLeft(headingFinder);
      final viewChipRect = tester.getRect(viewChipFinder);
      final refreshTopLeft = tester.getTopLeft(refreshButton);
      final cardTopBefore = tester.getTopLeft(firstCard).dy;
      final scrollRect = tester.getRect(scrollView);

      expect(
        scrollRect.top,
        greaterThanOrEqualTo(viewChipRect.bottom),
        reason: 'the scroll viewport should sit below the pinned view chips',
      );

      await tester.drag(scrollView, const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(firstCard).dy, lessThan(cardTopBefore));
      expect(tester.getTopLeft(headingFinder), headingTopLeft);
      expect(tester.getRect(viewChipFinder), viewChipRect);
      expect(tester.getTopLeft(refreshButton), refreshTopLeft);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('library filters stay fixed while the grid scrolls', (
    tester,
  ) async {
    await _pumpLibrary(
      tester,
      const Size(1000, 560),
      expandFilters: true,
      items: _scrollItems(),
    );
    final filters = find.byKey(const ValueKey('library-filter-panel'));
    final search = find.byKey(const ValueKey('library-search'));
    final scrollView = find.byType(CustomScrollView);
    final filterRect = tester.getRect(filters);
    final searchRect = tester.getRect(search);
    expect(
      tester.getRect(scrollView).top,
      greaterThanOrEqualTo(filterRect.bottom),
    );
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollView, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.getRect(filters), filterRect);
    expect(tester.getRect(search), searchRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resizing the library keeps thumbnail URLs stable for cache hits',
    (tester) async {
      const taggedItem = MediaItem(
        id: 'tagged-1',
        name: 'Tagged Series',
        type: MediaType.series,
        poster: MediaImageResource(
          urlTemplate: 'http://127.0.0.1:8096/Items/tagged-1/Images/Primary?maxWidth={width}&tag=poster',
          cacheKey: 'tagged-1:poster',
          headers: {'Authorization': 'poster-token'},
        ),
        backdrop: MediaImageResource(
          urlTemplate: 'http://127.0.0.1:8096/Items/tagged-1/Images/Backdrop?maxWidth={width}&tag=backdrop',
          cacheKey: 'tagged-1:backdrop',
          headers: {'Authorization': 'test'},
        ),
      );
      await _pumpLibrary(tester, const Size(1440, 900), items: [taggedItem]);
      final image = find.descendant(
        of: _posterFrameFinder(taggedItem.id),
        matching: find.byType(MediaImage),
      );
      final original = tester.widget<MediaImage>(image);
      expect(original.url, taggedItem.poster!.url());
      expect(original.headers, taggedItem.poster!.headers);

      for (final width in [1265.0, 980.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.widget<MediaImage>(image).url, original.url);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop library poster flies into detail page and flies back on return',
    (tester) async {
      final detailCompleter = Completer<MediaItem>();
      await _pumpRoutedLibrary(
        tester,
        size: const Size(1280, 900),
        loadItem: (_) => detailCompleter.future,
      );

      final posterFrame = _posterFrameFinder('b');
      expect(posterFrame, findsOneWidget);
      final cardRect = tester.getRect(posterFrame);

      await tester.tap(find.text('Series b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Even before detail metadata resolves, the poster is in flight inside
      // the navigator overlay between the card and detail positions.
      expect(posterFrame, findsOneWidget);
      expect(
        find.descendant(of: find.byType(Overlay), matching: posterFrame),
        findsOneWidget,
      );
      final pushMidRect = tester.getRect(posterFrame);
      expect(pushMidRect, isNot(equals(cardRect)));

      // Advance past the 300ms push transition while LoadingNotice still spins.
      await tester.pump(const Duration(milliseconds: 300));
      final detailRectWhileLoading = tester.getRect(posterFrame);
      expect(detailRectWhileLoading, isNot(equals(cardRect)));
      expect(
        _isStrictlyBetween(
          pushMidRect.left,
          cardRect.left,
          detailRectWhileLoading.left,
        ),
        isTrue,
      );
      expect(
        _isStrictlyBetween(
          pushMidRect.width,
          cardRect.width,
          detailRectWhileLoading.width,
        ),
        isTrue,
      );

      // Resolving the full item metadata must not shift the landed poster.
      detailCompleter.complete(
        const MediaItem(
          id: 'b',
          name: 'Series b',
          type: MediaType.movie,
          overview: 'Full metadata loaded.',
          genres: ['Animation', 'Drama'],
          productionYear: 2026,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(posterFrame), detailRectWhileLoading);

      // Returning flies the poster back from the detail hero to the card slot.
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final popMidRect = tester.getRect(posterFrame);
      expect(
        _isStrictlyBetween(
          popMidRect.left,
          detailRectWhileLoading.left,
          cardRect.left,
        ),
        isTrue,
      );
      expect(
        _isStrictlyBetween(
          popMidRect.width,
          detailRectWhileLoading.width,
          cardRect.width,
        ),
        isTrue,
      );

      await tester.pumpAndSettle();
      expect(tester.getRect(posterFrame), cardRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile series detail fades in without a jumping poster flight', (
    tester,
  ) async {
    final item = Completer<MediaItem>();
    await _pumpRoutedLibrary(
      tester,
      size: const Size(390, 900),
      loadItem: (id) => item.future,
    );

    final posterFrame = _posterFrameFinder('b');
    final cardRect = tester.getRect(posterFrame);
    expect(cardRect.width / cardRect.height, closeTo(2 / 3, 0.01));

    await tester.tap(find.text('Series b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // The card poster stays in place under the fade; nothing flies into
    // the wide phone artwork.
    expect(tester.getRect(posterFrame), cardRect);
    // The preview has no backdrop, so the artwork waits for full metadata
    // instead of showing the poster and swapping it out.
    expect(find.byKey(const ValueKey('detail-mobile-art')), findsNothing);

    item.complete(
      const MediaItem(
        id: 'b',
        name: 'Series b',
        type: MediaType.series,
        backdrop: MediaImageResource(
          urlTemplate:
              'http://127.0.0.1:8096/Items/b/Images/Backdrop?maxWidth={width}',
          cacheKey: 'b-backdrop',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-mobile-art')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-banner-title')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('detail-back')));
    await tester.pumpAndSettle();
    expect(tester.getRect(posterFrame), cardRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'app shell library branch animates poster hero on enter, mid-flight cancel and return',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final servers = MemoryServerRepository()..items = [_server];
      final container = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(language: 'en'),
          ),
          settingsRepositoryProvider.overrideWithValue(MemorySettings()),
          desktopWindowProvider.overrideWithValue(FakeWindow()),
          serverRepositoryProvider.overrideWithValue(servers),
          randomItemsProvider.overrideWith((ref) async => const []),
          resumeItemsProvider.overrideWith((ref) async => const []),
          latestItemsProvider.overrideWith((ref) async => const []),
          libraryViewsProvider.overrideWith(
            (ref) async => LibraryData(
              client: FakeMediaServerClient(server: _server),
              userId: 'user-1',
              views: const [
                MediaLibrary(
                  id: 'view',
                  name: 'Shows',
                  type: MediaLibraryType.tvShows,
                ),
              ],
            ),
          ),
          libraryItemsProvider.overrideWith2(_FakeItems.new),
          libraryItemProvider.overrideWith(
            (ref, query) async => MediaItem(
              id: query.itemId,
              name: 'Series ${query.itemId}',
              type: MediaType.movie,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SakugaApp(),
        ),
      );
      await tester.pumpAndSettle();

      container.read(routerProvider).go('/library');
      await tester.pumpAndSettle();

      final posterFrame = _posterFrameFinder('c');
      final cardRect = tester.getRect(posterFrame);

      // Start push flight, then reverse mid-flight via router.pop().
      await tester.tap(find.text('Series c'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final divertedFrom = tester.getRect(posterFrame);
      expect(divertedFrom, isNot(equals(cardRect)));

      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(tester.getRect(posterFrame), cardRect);

      // Full enter and full return through the pinned back button.
      await tester.tap(find.text('Series c'));
      await tester.pumpAndSettle();
      final detailRect = tester.getRect(posterFrame);
      expect(detailRect, isNot(equals(cardRect)));

      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final returningRect = tester.getRect(posterFrame);
      expect(
        _isStrictlyBetween(returningRect.left, detailRect.left, cardRect.left),
        isTrue,
      );

      await tester.pumpAndSettle();
      expect(tester.getRect(posterFrame), cardRect);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile shell aligns library refresh and detail back button inline with header title',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final servers = MemoryServerRepository()..items = [_server];
      final container = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(language: 'en'),
          ),
          settingsRepositoryProvider.overrideWithValue(MemorySettings()),
          desktopWindowProvider.overrideWithValue(
            FakeWindow(available: true, macOS: true),
          ),
          serverRepositoryProvider.overrideWithValue(servers),
          randomItemsProvider.overrideWith((ref) async => const []),
          resumeItemsProvider.overrideWith((ref) async => const []),
          latestItemsProvider.overrideWith((ref) async => const []),
          libraryViewsProvider.overrideWith(
            (ref) async => LibraryData(
              client: FakeMediaServerClient(server: _server),
              userId: 'user-1',
              views: const [
                MediaLibrary(
                  id: 'view',
                  name: 'Shows',
                  type: MediaLibraryType.tvShows,
                ),
              ],
            ),
          ),
          libraryItemsProvider.overrideWith2(_FakeItems.new),
          libraryItemProvider.overrideWith(
            (ref, query) async => MediaItem(
              id: query.itemId,
              name: 'Series ${query.itemId}',
              type: MediaType.movie,
              overview: List.filled(20, 'A long mobile synopsis.').join(' '),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SakugaApp(),
        ),
      );
      await tester.pumpAndSettle();

      container.read(routerProvider).go('/library');
      await tester.pumpAndSettle();

      final headerTitle = find.descendant(
        of: find.byKey(const ValueKey('mobile-header')),
        matching: find.text('Library'),
      );
      final refreshButton = find.byKey(const ValueKey('library-refresh'));
      final backButton = find.byKey(const ValueKey('detail-back'));
      final viewChipButton = find.ancestor(
        of: find.text('Shows'),
        matching: find.byType(FButton),
      );
      final rightCard = find.byKey(const ValueKey('library-mobile-card-b'));

      expect(headerTitle, findsOneWidget);
      expect(refreshButton, findsOneWidget);
      expect(backButton, findsNothing);

      final titleRectOnLibrary = tester.getRect(headerTitle);
      final refreshRect = tester.getRect(refreshButton);
      expect(refreshRect.center.dy, closeTo(titleRectOnLibrary.center.dy, 1.0));
      expect(refreshRect.left, greaterThan(titleRectOnLibrary.left));
      expect(
        titleRectOnLibrary.left,
        closeTo(tester.getRect(viewChipButton).left, 1),
      );
      expect(refreshRect.right, closeTo(tester.getRect(rightCard).right, 1));

      // Opening a detail page replaces the right refresh button with a single
      // back button to the left of the series title on the same row.
      await tester.tap(find.text('Series a'));
      await tester.pumpAndSettle();

      expect(refreshButton, findsNothing);
      expect(backButton, findsOneWidget);

      final detailTitle = find.descendant(
        of: find.byKey(const ValueKey('mobile-header')),
        matching: find.text('Series a'),
      );
      expect(detailTitle, findsOneWidget);
      final titleRectOnDetail = tester.getRect(detailTitle);
      final backRect = tester.getRect(backButton);
      expect(backRect.center.dy, closeTo(titleRectOnDetail.center.dy, 1.0));
      expect(backRect.right, lessThanOrEqualTo(titleRectOnDetail.left));

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(backButton, findsNothing);
      expect(refreshButton, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

List<MediaItem> _scrollItems() => [
  _item('a', 0.5),
  for (var i = 0; i < 20; i++) _item('scroll-$i', 0.7),
];

void _expectDurationBadge(
  WidgetTester tester,
  String duration,
  Rect thumbnail,
) {
  final badge = tester.getRect(find.text(duration));
  expect(
    thumbnail.contains(badge.topLeft),
    isTrue,
    reason: '$badge vs $thumbnail',
  );
  expect(
    thumbnail.contains(badge.bottomRight),
    isTrue,
    reason: '$badge vs $thumbnail',
  );
  expect(badge.center.dx, greaterThanOrEqualTo(thumbnail.center.dx - 0.01));
  expect(badge.center.dy, lessThan(thumbnail.center.dy));
}

Finder _posterFrameFinder(String id) =>
    find.byKey(ValueKey(('poster-hero-frame', posterHeroTag(id))));

bool _isStrictlyBetween(double value, double a, double b) {
  final min = a < b ? a : b;
  final max = a < b ? b : a;
  return value > min && value < max;
}

Future<void> _pumpRoutedLibrary(
  WidgetTester tester, {
  required Size size,
  required FutureOr<MediaItem> Function(String itemId) loadItem,
  FakeMediaServerClient? client,
  List<MediaItem>? items,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final router = GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, _) => const LibraryPage(),
        routes: [
          GoRoute(
            path: ':itemId',
            pageBuilder: (_, state) => buildDetailTransitionPage(state),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  final servers = MemoryServerRepository()..items = [_server];
  final container = ProviderContainer(
    overrides: [
      serverRepositoryProvider.overrideWithValue(servers),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: client ?? FakeMediaServerClient(server: _server),
          userId: 'user-1',
          views: const [
            MediaLibrary(
              id: 'view',
              name: 'Shows',
              type: MediaLibraryType.tvShows,
            ),
          ],
        ),
      ),
      libraryItemsProvider.overrideWith2(
        (query) => _FakeItems(query, items: items),
      ),
      libraryItemProvider.overrideWith((ref, query) => loadItem(query.itemId)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(language: 'en'),
            brightness: Brightness.light,
            touch: size.width < 600,
          ),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
