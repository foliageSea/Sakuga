import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_models.dart';
import 'package:sakuga/data/jellyfin/server_profile.dart';
import 'package:sakuga/data/jellyfin/server_repository.dart';
import 'package:sakuga/features/detail/detail_page.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_page.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/media_widgets.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

JellyfinItem _item(String id, double ratio) => JellyfinItem(
  id: id,
  name: 'Series $id',
  type: 'Series',
  imageTags: const {},
  primaryImageAspectRatio: ratio,
);

class _FakeItems extends LibraryItemsController {
  _FakeItems(super.query);

  @override
  Future<LibraryItemsState> build() async {
    final items = [
      _item('a', 0.5),
      _item('b', 1.2),
      _item('c', 0.7),
      _item('d', 0.7),
    ];
    return LibraryItemsState(items: items, totalRecordCount: items.length);
  }
}

Future<void> _pumpLibrary(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final servers = MemoryServerRepository()..items = [_server];
  final container = ProviderContainer(
    overrides: [
      serverRepositoryProvider.overrideWithValue(servers),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: JellyfinClient(server: _server),
          userId: 'user-1',
          views: const [
            JellyfinView(id: 'view', name: 'Shows', collectionType: 'tvshows'),
          ],
        ),
      ),
      libraryItemsProvider.overrideWith2(_FakeItems.new),
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
}

void main() {
  testWidgets('mobile library flows posters into two staggered columns', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(390, 900));

    expect(
      find.byKey(const ValueKey('library-mobile-masonry')),
      findsOneWidget,
    );
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
    expect(third.dx, second.dx);
    expect(third.dy, greaterThan(second.dy));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('library-mobile-card-a')))
          .height,
      greaterThan(
        tester
            .getSize(find.byKey(const ValueKey('library-mobile-card-b')))
            .height,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop library keeps the aligned grid', (tester) async {
    await _pumpLibrary(tester, const Size(1280, 900));

    expect(find.byKey(const ValueKey('library-mobile-masonry')), findsNothing);
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
    expect(refreshRect.right, closeTo(fourthCardRect.right, 1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'library scrolls inside the grid while keeping heading and view chips pinned',
    (tester) async {
      await _pumpLibrary(tester, const Size(1000, 560));

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

  testWidgets('resizing the library keeps poster URLs stable for cache hits', (
    tester,
  ) async {
    const client = ServerProfile(
      id: 'server',
      name: 'Test server',
      baseUrl: 'http://127.0.0.1:8096',
      apiKey: 'test-key',
    );
    const taggedItem = JellyfinItem(
      id: 'tagged-1',
      name: 'Tagged Series',
      type: 'Series',
      imageTags: {'Primary': 'tag-123'},
    );
    final jellyfin = JellyfinClient(server: client);
    String? capturedUrl;

    for (final width in [1440.0, 1265.0, 980.0, 390.0]) {
      await tester.pumpWidget(
        MaterialApp(
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
              touch: width < 600,
            ),
            child: child!,
          ),
          home: Center(
            child: SizedBox(
              width: width / 4,
              child: MediaPosterCard(
                client: jellyfin,
                item: taggedItem,
                onPosterTap: (url) => capturedUrl = url,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tagged Series'));
      expect(
        capturedUrl,
        'http://127.0.0.1:8096/Items/tagged-1/Images/Primary?maxWidth=600&tag=tag-123',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop library poster flies into detail page and flies back on return',
    (tester) async {
      final detailCompleter = Completer<JellyfinItem>();
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
        const JellyfinItem(
          id: 'b',
          name: 'Series b',
          type: 'Movie',
          imageTags: {},
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

  testWidgets(
    'mobile masonry poster morphs into detail page and back on return',
    (tester) async {
      await _pumpRoutedLibrary(
        tester,
        size: const Size(390, 900),
        loadItem: (id) async => JellyfinItem(
          id: id,
          name: 'Series $id',
          type: 'Movie',
          imageTags: const {},
          primaryImageAspectRatio: 1.2,
          overview: 'Mobile detail view.',
        ),
      );

      // Card 'b' has a landscape 1.2 ratio in the masonry grid, while the
      // detail page renders a 2:3 portrait poster.
      final posterFrame = _posterFrameFinder('b');
      final cardRect = tester.getRect(posterFrame);
      expect(cardRect.width / cardRect.height, closeTo(1.2, 0.01));

      await tester.tap(find.text('Series b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      final pushMidRect = tester.getRect(posterFrame);
      final pushMidRatio = pushMidRect.width / pushMidRect.height;
      expect(_isStrictlyBetween(pushMidRatio, 1.2, 2 / 3), isTrue);

      await tester.pumpAndSettle();
      final detailRect = tester.getRect(posterFrame);
      expect(detailRect.width / detailRect.height, closeTo(2 / 3, 0.01));

      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final popMidRect = tester.getRect(posterFrame);
      final popMidRatio = popMidRect.width / popMidRect.height;
      expect(_isStrictlyBetween(popMidRatio, 2 / 3, 1.2), isTrue);

      await tester.pumpAndSettle();
      expect(tester.getRect(posterFrame), cardRect);
      expect(tester.takeException(), isNull);
    },
  );

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
              client: JellyfinClient(server: _server),
              userId: 'user-1',
              views: const [
                JellyfinView(
                  id: 'view',
                  name: 'Shows',
                  collectionType: 'tvshows',
                ),
              ],
            ),
          ),
          libraryItemsProvider.overrideWith2(_FakeItems.new),
          libraryItemProvider.overrideWith(
            (ref, query) async => JellyfinItem(
              id: query.itemId,
              name: 'Series ${query.itemId}',
              type: 'Movie',
              imageTags: const {},
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
              client: JellyfinClient(server: _server),
              userId: 'user-1',
              views: const [
                JellyfinView(
                  id: 'view',
                  name: 'Shows',
                  collectionType: 'tvshows',
                ),
              ],
            ),
          ),
          libraryItemsProvider.overrideWith2(_FakeItems.new),
          libraryItemProvider.overrideWith(
            (ref, query) async => JellyfinItem(
              id: query.itemId,
              name: 'Series ${query.itemId}',
              type: 'Movie',
              imageTags: const {},
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
      // back button to the left of the "Library" header title on the same row.
      await tester.tap(find.text('Series a'));
      await tester.pumpAndSettle();

      expect(refreshButton, findsNothing);
      expect(backButton, findsOneWidget);

      final titleRectOnDetail = tester.getRect(headerTitle);
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
  required FutureOr<JellyfinItem> Function(String itemId) loadItem,
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
          client: JellyfinClient(server: _server),
          userId: 'user-1',
          views: const [
            JellyfinView(id: 'view', name: 'Shows', collectionType: 'tvshows'),
          ],
        ),
      ),
      libraryItemsProvider.overrideWith2(_FakeItems.new),
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
