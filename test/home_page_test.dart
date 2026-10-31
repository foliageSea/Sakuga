import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/app/shell.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/home/home_page.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/widgets.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

MediaItem _resumableEpisode() => const MediaItem(
  id: 'episode-1',
  name: 'Pilot',
  type: MediaType.episode,
  seriesId: 'series-1',
  seriesName: 'Resumed Series',
  seasonId: 'season-1',
  indexNumber: 1,
  parentIndexNumber: 1,
  reportedPlayedPercentage: 42.0,
);

MediaItem _series() => const MediaItem(
  id: 'series-2',
  name: 'Recent Series',
  type: MediaType.series,
);

/// Pumps the home page behind a router whose destination routes are stubs, so
/// the test only checks where a card tap navigates.
Future<void> pumpHome(
  WidgetTester tester, {
  List<MediaItem>? carousel,
  List<MediaItem>? resume,
  List<MediaItem>? latest,
  Size size = const Size(1280, 1200),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/library/:itemId',
        builder: (_, state) => Text('detail:${state.pathParameters['itemId']}'),
      ),
      GoRoute(
        path: '/player',
        builder: (_, state) =>
            Text('player:${state.uri.queryParameters['item']}'),
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
          client: FakeMediaServerClient(server: _server),
          userId: 'user-1',
          views: const [],
        ),
      ),
      randomItemsProvider.overrideWith(
        (ref) async => carousel ?? const <MediaItem>[],
      ),
      resumeItemsProvider.overrideWith(
        (ref) async => resume ?? [_resumableEpisode()],
      ),
      latestItemsProvider.overrideWith((ref) async => latest ?? [_series()]),
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
            touch: false,
          ),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapCard(WidgetTester tester, String title) async {
  final card = find.text(title);
  expect(card, findsOneWidget);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

const _loopItems = [
  MediaItem(id: 'loop-1', name: 'Loop One', type: MediaType.movie),
  MediaItem(id: 'loop-2', name: 'Loop Two', type: MediaType.movie),
  MediaItem(id: 'loop-3', name: 'Loop Three', type: MediaType.movie),
];

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('home refresh reloads all sections at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <String, int>{};
      Future<List<MediaItem>> load(String section) async {
        calls.update(section, (value) => value + 1, ifAbsent: () => 1);
        return [];
      }

      final servers = MemoryServerRepository()..items = [_server];
      final container = ProviderContainer(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(language: 'en'),
          ),
          settingsRepositoryProvider.overrideWithValue(MemorySettings()),
          desktopWindowProvider.overrideWithValue(FakeWindow(available: false)),
          serverRepositoryProvider.overrideWithValue(servers),
          libraryViewsProvider.overrideWith(
            (ref) async => LibraryData(
              client: FakeMediaServerClient(server: _server),
              userId: 'user-1',
              views: const [],
            ),
          ),
          randomItemsProvider.overrideWith((ref) => load('carousel')),
          resumeItemsProvider.overrideWith((ref) => load('resume')),
          latestItemsProvider.overrideWith((ref) => load('latest')),
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
      final refresh = find.byKey(const ValueKey('home-refresh'));
      expect(refresh, findsOneWidget);
      final before = Map<String, int>.from(calls);
      expect(before.keys, containsAll(['carousel', 'resume', 'latest']));
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      for (final section in before.keys) {
        expect(calls[section], greaterThan(before[section]!));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('carousel arrows cross boundaries in the same direction', (
    tester,
  ) async {
    await pumpHome(tester, carousel: _loopItems);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );

    // Moving backwards from the first item goes straight to the last item.
    await tester.tap(find.byKey(const ValueKey('home-carousel-prev')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.page, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(container.read(homeCarouselIndexProvider), 2);
    expect(find.text('Loop Three'), findsOneWidget);

    // Moving forwards from the last item continues forwards to the first.
    await tester.tap(find.byKey(const ValueKey('home-carousel-next')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.page, inExclusiveRange(3, 4));
    await tester.pumpAndSettle();
    expect(container.read(homeCarouselIndexProvider), 0);
    expect(find.text('Loop One'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-carousel-dot-1')));
    await tester.pumpAndSettle();
    expect(container.read(homeCarouselIndexProvider), 1);
    expect(find.text('Loop Two'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  ]) {
    testWidgets('carousel swipes loop both ways with ${kind.name}', (
      tester,
    ) async {
      await pumpHome(tester, carousel: _loopItems);
      final page = find.byType(PageView);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomePage)),
      );
      final width = tester.getSize(page).width;
      // Repeated backward swipes cross the first/last boundary twice.
      for (final expected in [2, 1, 0, 2]) {
        await tester.drag(page, Offset(width * 0.7, 0), kind: kind);
        await tester.pumpAndSettle();
        expect(container.read(homeCarouselIndexProvider), expected);
      }
      for (final expected in [0, 1, 2, 0]) {
        await tester.drag(page, Offset(-width * 0.7, 0), kind: kind);
        await tester.pumpAndSettle();
        expect(container.read(homeCarouselIndexProvider), expected);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('carousel autoplay continues forwards across repeated loops', (
    tester,
  ) async {
    await pumpHome(tester, carousel: _loopItems);
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    for (var step = 1; step <= 7; step++) {
      final start = controller.page!;
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.page, greaterThan(start));
      expect(controller.page, lessThan(start + 1));
      await tester.pumpAndSettle();
      expect(container.read(homeCarouselIndexProvider), step % 3);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('single carousel item stays still without loop controls', (
    tester,
  ) async {
    await pumpHome(tester, carousel: [_loopItems.first]);
    expect(find.byKey(const ValueKey('home-carousel-prev')), findsNothing);
    expect(find.byKey(const ValueKey('home-carousel-next')), findsNothing);
    await tester.pump(const Duration(seconds: 12));
    expect(find.text('Loop One'), findsOneWidget);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.touch,
  ]) {
    testWidgets(
      'home media rows scroll both ways with ${kind.name}',
      (tester) async {
        await pumpHome(
          tester,
          resume: List.generate(10, (_) => _resumableEpisode()),
          latest: List.generate(10, (_) => _series()),
        );
        final rows = find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        );
        expect(rows, findsNWidgets(2));
        for (var index = 0; index < 2; index++) {
          final row = rows.at(index);
          final scrollable = find
              .descendant(of: row, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          final otherRow = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: rows.at(1 - index),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          final page = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(CustomScrollView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          final otherOffset = otherRow.pixels;
          final pageOffset = page.pixels;
          await tester.drag(row, const Offset(-240, 0), kind: kind);
          await tester.pumpAndSettle();
          final forwardOffset = position.pixels;
          expect(forwardOffset, greaterThan(0));
          await tester.drag(row, const Offset(160, 0), kind: kind);
          await tester.pumpAndSettle();
          expect(position.pixels, lessThan(forwardOffset));
          expect(otherRow.pixels, otherOffset);
          expect(page.pixels, pageOffset);
          expect(find.byType(HomePage), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(
        kind == PointerDeviceKind.touch
            ? TargetPlatform.android
            : TargetPlatform.macOS,
      ),
    );
  }

  testWidgets('home content scrolls below the fixed title and refresh button', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1280, 500), carousel: _loopItems);
    final heading = find.text('Home');
    final refresh = find.byKey(const ValueKey('home-refresh'));
    final viewport = find.byType(CustomScrollView);
    final headingRect = tester.getRect(heading);
    final refreshRect = tester.getRect(refresh);
    final carousel = find.byKey(const ValueKey('home-poster-carousel'));
    final carouselTop = tester.getTopLeft(carousel).dy;
    expect(
      tester.getRect(viewport).top,
      greaterThanOrEqualTo(refreshRect.bottom),
    );
    await tester.drag(viewport, const Offset(0, -180));
    await tester.pump();
    expect(tester.getTopLeft(carousel).dy, lessThan(carouselTop));
    expect(tester.getRect(heading), headingRect);
    expect(tester.getRect(refresh), refreshRect);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('vertical wheel scroll over media rows scrolls the home page', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1280, 420));
    final page = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    final row = find
        .byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        )
        .first;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(row),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();
    expect(page.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('continue watching resumes the episode in the player', (
    tester,
  ) async {
    await pumpHome(tester);

    await _tapCard(tester, 'Resumed Series');

    expect(find.text('player:episode-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resumable series opens its detail page', (tester) async {
    await pumpHome(tester, resume: [_series()], latest: const []);

    await _tapCard(tester, 'Recent Series');

    expect(find.text('detail:series-2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recently added opens the detail page', (tester) async {
    await pumpHome(tester);

    await _tapCard(tester, 'Recent Series');

    expect(find.text('detail:series-2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('media cards wrap their content without fixed blank space', (
    tester,
  ) async {
    await pumpHome(tester);

    final continueCard = find
        .ancestor(
          of: find.text('Resumed Series'),
          matching: find.byType(Surface),
        )
        .first;
    final recentCard = find
        .ancestor(
          of: find.text('Recent Series'),
          matching: find.byType(Surface),
        )
        .first;

    expect(tester.getSize(continueCard).height, lessThan(240));
    expect(tester.getSize(recentCard).height, lessThan(310));
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .where(
          (text) =>
              text.data == 'Resumed Series' || text.data == 'Recent Series',
        );
    expect(titles, isNotEmpty);
    for (final title in titles) {
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final card in [continueCard, recentCard]) {
      final restingRect = tester.getRect(card);
      final title = find
          .descendant(of: card, matching: find.byType(Text))
          .first;
      final restingTitleRect = tester.getRect(title);
      await mouse.moveTo(restingRect.center + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(tester.getRect(card), isNot(restingRect));
      expect(tester.getRect(title), isNot(restingTitleRect));

      // Moving within the card changes its tilt without changing layout size.
      final hoveredRect = tester.getRect(card);
      await mouse.moveTo(restingRect.center - const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(tester.getRect(card), isNot(hoveredRect));
      expect(tester.getSize(card), restingRect.size);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.getRect(card), restingRect);
      expect(tester.getRect(title), restingTitleRect);
    }
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home random poster carousel rotates and updates global window blurred background',
    (tester) async {
      const windowSize = Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = windowSize;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const carouselItems = [
        MediaItem(
          id: 'featured-1',
          name: 'Sunflower Circus',
          type: MediaType.series,
          poster: MediaImageResource(
            urlTemplate: 'http://127.0.0.1:8096/Items/featured-1/Images/Primary?maxWidth={width}&tag=poster-a',
            cacheKey: 'featured-1:poster-a',
          ),
          backdrop: MediaImageResource(
            urlTemplate: 'http://127.0.0.1:8096/Items/featured-1/Images/Backdrop/0?maxWidth={width}&tag=backdrop-a',
            cacheKey: 'featured-1:backdrop-a',
          ),
          overview: 'A troupe of performers travelling across Japan.',
          genres: ['Animation', 'Drama'],
          productionYear: 2026,
          officialRating: 'PG-13',
        ),
        MediaItem(
          id: 'featured-2',
          name: 'Starlight Sonata',
          type: MediaType.movie,
          poster: MediaImageResource(
            urlTemplate: 'http://127.0.0.1:8096/Items/featured-2/Images/Primary?maxWidth={width}&tag=poster-b',
            cacheKey: 'featured-2:poster-b',
          ),
          overview: 'An orchestral fantasy film.',
          genres: ['Fantasy'],
          productionYear: 2025,
        ),
      ];

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
          libraryViewsProvider.overrideWith(
            (ref) async => LibraryData(
              client: FakeMediaServerClient(server: _server),
              userId: 'user-1',
              views: const [],
            ),
          ),
          randomItemsProvider.overrideWith((ref) async => carouselItems),
          resumeItemsProvider.overrideWith((ref) async => const []),
          latestItemsProvider.overrideWith((ref) async => const []),
          libraryItemProvider.overrideWith(
            (ref, query) async => carouselItems.firstWhere(
              (item) => item.id == query.itemId,
              orElse: () => carouselItems.first,
            ),
          ),
          seriesSeasonsProvider.overrideWith((ref, query) async => const []),
          seriesEpisodesProvider.overrideWith((ref, query) async => const []),
        ],
      );
      addTearDown(container.dispose);

      Future<void> pumpFrames([int count = 6]) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SakugaApp(),
        ),
      );
      await pumpFrames();

      final carouselFinder = find.byKey(const ValueKey('home-poster-carousel'));
      final bgFinder = find.byKey(const ValueKey('window-poster-background'));
      final blurMaskFinder = find.byKey(
        const ValueKey('window-poster-blur-mask'),
      );

      // Server summary is replaced by the random poster carousel, and the
      // global window blurred background spans the entire window.
      expect(find.text('Test server'), findsNothing);
      expect(carouselFinder, findsOneWidget);
      expect(find.text('Sunflower Circus'), findsOneWidget);
      expect(tester.getRect(bgFinder), Offset.zero & windowSize);
      expect(tester.getRect(find.byType(DesktopTitleBar)).top, 0);
      expect(tester.getRect(find.byType(FSidebar)).left, 0);
      expect(blurMaskFinder, findsOneWidget);
      expect(
        tester.widget<BackdropFilter>(blurMaskFinder).filter,
        ImageFilter.blur(sigmaX: 20, sigmaY: 20, tileMode: TileMode.clamp),
      );

      Iterable<String> activeBackgroundUrls() => tester
          .widgetList<CachedNetworkImage>(
            find.descendant(
              of: bgFinder,
              matching: find.byType(CachedNetworkImage),
            ),
          )
          .map((img) => img.imageUrl);

      expect(
        activeBackgroundUrls(),
        contains(
          'http://127.0.0.1:8096/Items/featured-1/Images/Primary?maxWidth=600&tag=poster-a',
        ),
      );

      // Auto-play after 6s advances to the second slide and crossfades the
      // global window poster background to poster-b.
      await tester.pump(const Duration(seconds: 6));
      await pumpFrames();
      expect(find.text('Starlight Sonata'), findsOneWidget);
      expect(
        activeBackgroundUrls(),
        contains(
          'http://127.0.0.1:8096/Items/featured-2/Images/Primary?maxWidth=600&tag=poster-b',
        ),
      );

      // The library inherits the currently selected carousel poster.
      container.read(routerProvider).go('/library');
      await pumpFrames();
      expect(tester.getRect(bgFinder), Offset.zero & windowSize);
      expect(blurMaskFinder, findsOneWidget);
      expect(
        activeBackgroundUrls(),
        contains(
          'http://127.0.0.1:8096/Items/featured-2/Images/Primary?maxWidth=600&tag=poster-b',
        ),
      );

      container.read(routerProvider).go('/home');
      await pumpFrames();
      expect(find.text('Starlight Sonata'), findsOneWidget);

      // Clicking the previous arrow returns to the first slide.
      await tester.tap(find.byKey(const ValueKey('home-carousel-prev')));
      await pumpFrames();
      expect(find.text('Sunflower Circus'), findsOneWidget);
      expect(
        activeBackgroundUrls(),
        contains(
          'http://127.0.0.1:8096/Items/featured-1/Images/Primary?maxWidth=600&tag=poster-a',
        ),
      );

      // Switching to settings hides the global blurred poster background.
      container.read(routerProvider).go('/settings');
      await pumpFrames();
      expect(blurMaskFinder, findsNothing);

      // Returning to home restores it, and tapping the slide opens its detail
      // page while keeping the global blurred poster background active.
      container.read(routerProvider).go('/home');
      await pumpFrames();
      expect(blurMaskFinder, findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('home-carousel-slide-featured-1')),
      );
      await pumpFrames();
      expect(find.byKey(const ValueKey('detail-back')), findsOneWidget);
      expect(blurMaskFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
