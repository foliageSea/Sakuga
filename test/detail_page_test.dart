import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/detail/detail_page.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/media_widgets.dart';
import 'package:sakuga/shared/widgets.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

const _title = 'A Long Movie Title For The Detail Page';

/// A movie tall enough that the detail page always scrolls, with no image tags
/// so the test never touches the network or the on-disk image cache.
MediaItem _movie() => MediaItem(
  id: 'movie-1',
  name: _title,
  type: MediaType.movie,
  overview: List.filled(
    24,
    'An animated feature about a travelling theatre troupe.',
  ).join(' '),
  genres: const ['Animation', 'Drama'],
  studios: const ['Sakuga Studio'],
  officialRating: 'PG-13',
  productionYear: 2026,
  people: [
    for (var i = 0; i < 12; i++)
      MediaPerson(
        id: 'person-$i',
        name: 'Person $i',
        role: 'Role $i',
        type: 'Actor',
      ),
  ],
);

MediaItem _series() => const MediaItem(
  id: 'series-1',
  name: 'A Series With Episodes',
  type: MediaType.series,
  overview: 'A short synopsis.',
  genres: ['Animation'],
  productionYear: 2026,
);

MediaItem _season() =>
    const MediaItem(id: 'season-1', name: 'Season 1', type: MediaType.season);

MediaItem _episode() => const MediaItem(
  id: 'episode-1',
  name: 'Pilot',
  type: MediaType.episode,
  seriesId: 'series-1',
  seriesName: 'A Series With Episodes',
  seasonId: 'season-1',
  indexNumber: 1,
  parentIndexNumber: 1,
);

/// Pumps the real detail route behind a router so the back button can pop.
Future<GoRouter> pumpDetailPage(
  WidgetTester tester, {
  required FutureOr<MediaItem> Function() item,
  Size size = const Size(1280, 800),
  bool settle = true,
  bool withPlayerRoute = false,
  List<MediaItem>? seasons,
  List<MediaItem>? episodes,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final router = GoRouter(
    initialLocation: '/library/movie-1',
    routes: [
      GoRoute(
        path: '/library',
        builder: (_, _) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: ':itemId',
            builder: (_, state) =>
                DetailPage(itemId: state.pathParameters['itemId']!),
          ),
        ],
      ),
      if (withPlayerRoute)
        GoRoute(
          path: '/player',
          builder: (_, state) =>
              Text('player:${state.uri.queryParameters['item']}'),
        ),
    ],
  );
  addTearDown(router.dispose);

  final container = ProviderContainer(
    overrides: [
      if (seasons != null)
        seriesSeasonsProvider.overrideWith((ref, query) => seasons),
      if (episodes != null)
        seriesEpisodesProvider.overrideWith((ref, query) => episodes),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: FakeMediaServerClient(server: _server),
          userId: 'user-1',
          views: const [],
        ),
      ),
      libraryItemProvider.overrideWith((ref, query) => item()),
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
  }
  return router;
}

Finder get _backButton => find.byKey(const ValueKey('detail-back'));

ScrollPosition _pageScrollPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(CustomScrollView),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable).position;
}

/// Scrolls the page by [dy] and checks that the back button kept its place
/// while the page content moved.
Future<void> expectBackButtonPinned(
  WidgetTester tester, {
  double dy = -320,
}) async {
  expect(_backButton, findsOneWidget);
  final pinnedAt = tester.getTopLeft(_backButton);
  final titleBefore = tester.getTopLeft(find.text(_title)).dy;

  final position = _pageScrollPosition(tester);
  expect(
    position.maxScrollExtent,
    greaterThan(0),
    reason: 'the page should have enough content to scroll',
  );

  await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
  await tester.pumpAndSettle();

  expect(position.pixels, greaterThan(0));
  expect(
    tester.getTopLeft(find.text(_title)).dy,
    lessThan(titleBefore),
    reason: 'the content should scroll under the pinned back button',
  );
  expect(tester.getTopLeft(_backButton), pinnedAt);
}

void main() {
  testWidgets('the back button stays pinned while the detail page scrolls', (
    tester,
  ) async {
    await pumpDetailPage(tester, item: _movie);
    await expectBackButtonPinned(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back button stays pinned on the mobile layout', (
    tester,
  ) async {
    await pumpDetailPage(tester, item: _movie, size: const Size(390, 844));
    await expectBackButtonPinned(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pinned back button pops the detail route', (tester) async {
    await pumpDetailPage(tester, item: _movie);
    expect(_backButton, findsOneWidget);

    await tester.tap(_backButton);
    await tester.pumpAndSettle();

    expect(_backButton, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back button is available while the item loads', (
    tester,
  ) async {
    final completer = Completer<MediaItem>();
    await pumpDetailPage(tester, item: () => completer.future, settle: false);

    expect(_backButton, findsOneWidget);
    expect(find.byType(FCircularProgress), findsOneWidget);
  });

  testWidgets('the back button is available when the item fails to load', (
    tester,
  ) async {
    await pumpDetailPage(
      tester,
      item: () async => throw const AppException(FailureKind.network),
    );

    expect(_backButton, findsOneWidget);
    expect(find.byType(ErrorNotice), findsOneWidget);
  });

  testWidgets('tapping an episode opens the player for that episode', (
    tester,
  ) async {
    final episode = _episode();
    await pumpDetailPage(
      tester,
      item: _series,
      size: const Size(1280, 1000),
      withPlayerRoute: true,
      seasons: [_season()],
      episodes: [episode],
    );

    await tester.ensureVisible(find.text(episode.name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(episode.name));
    await tester.pumpAndSettle();

    expect(find.text('player:${episode.id}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode tiles echo watch progress bar for resumed episodes', (
    tester,
  ) async {
    const partialEpisode = MediaItem(
      id: 'episode-1',
      name: 'Pilot',
      type: MediaType.episode,
      seriesId: 'series-1',
      seriesName: 'A Series With Episodes',
      seasonId: 'season-1',
      indexNumber: 1,
      parentIndexNumber: 1,
      runtime: Duration(seconds: 100),
      playbackPosition: Duration(seconds: 45),
    );
    await pumpDetailPage(
      tester,
      item: _series,
      size: const Size(1280, 1000),
      seasons: [_season()],
      episodes: [
        partialEpisode,
        const MediaItem(
          id: 'episode-2',
          name: 'Second',
          type: MediaType.episode,
          seriesId: 'series-1',
          indexNumber: 2,
          parentIndexNumber: 1,
        ),
      ],
    );

    final bar = tester.widget<MediaProgressBar>(find.byType(MediaProgressBar));
    expect(bar.value, closeTo(0.45, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail page uses series poster as global window background with Gaussian blur mask',
    (tester) async {
      const windowSize = Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = windowSize;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const taggedSeries = MediaItem(
        id: 'series-bg',
        name: 'Circus Troupe',
        type: MediaType.series,
        poster: MediaImageResource(
          urlTemplate: 'http://127.0.0.1:8096/Items/series-bg/Images/Primary?maxWidth={width}&tag=poster-tag-1',
          cacheKey: 'series-bg:poster-tag-1',
        ),
        overview: 'A travelling circus story.',
        genres: ['Animation'],
        productionYear: 2026,
      );
      final detailCompleter = Completer<MediaItem>();
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
          libraryItemsProvider.overrideWith2(_TaggedLibraryItems.new),
          libraryItemProvider.overrideWith(
            (ref, query) => detailCompleter.future,
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

      final bgFinder = find.byKey(const ValueKey('window-poster-background'));
      final blurMaskFinder = find.byKey(
        const ValueKey('window-poster-blur-mask'),
      );

      // Home branch has no blur mask active.
      expect(bgFinder, findsOneWidget);
      expect(blurMaskFinder, findsNothing);

      container.read(routerProvider).go('/library');
      await pumpFrames();
      expect(blurMaskFinder, findsNothing);

      // Tapping the series card immediately mounts the global blurred poster
      // background across the full window (title bar + sidebar + content)
      // even before full detail metadata resolves.
      await tester.tap(find.text('Circus Troupe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(tester.getRect(bgFinder), Offset.zero & windowSize);
      expect(tester.getRect(find.byType(DesktopTitleBar)).top, 0);
      expect(tester.getRect(find.byType(FSidebar)).left, 0);
      expect(blurMaskFinder, findsOneWidget);

      final blur = tester.widget<BackdropFilter>(blurMaskFinder);
      expect(
        blur.filter,
        ImageFilter.blur(sigmaX: 64, sigmaY: 64, tileMode: TileMode.clamp),
      );

      final bgImage = tester.widget<CachedNetworkImage>(
        find.descendant(
          of: bgFinder,
          matching: find.byType(CachedNetworkImage),
        ),
      );
      expect(
        bgImage.imageUrl,
        'http://127.0.0.1:8096/Items/series-bg/Images/Primary?maxWidth=600&tag=poster-tag-1',
      );

      // Resolving full metadata keeps the global blurred poster background.
      detailCompleter.complete(taggedSeries);
      await pumpFrames();
      expect(blurMaskFinder, findsOneWidget);

      // Toggling dark mode updates the mask cleanly without errors.
      await tester.tap(find.byKey(const ValueKey('toggle-theme')));
      await pumpFrames(3);
      expect(blurMaskFinder, findsOneWidget);

      // Switching to another sidebar branch fades out and removes the blur mask.
      container.read(routerProvider).go('/home');
      await pumpFrames();
      expect(blurMaskFinder, findsNothing);

      // Returning to the detail route restores the global blurred background,
      // and popping back to the library removes it again.
      container.read(routerProvider).go('/library/series-bg');
      await pumpFrames();
      expect(blurMaskFinder, findsOneWidget);

      await tester.tap(_backButton);
      await pumpFrames();
      expect(blurMaskFinder, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TaggedLibraryItems extends LibraryItemsController {
  _TaggedLibraryItems(super.query);

  @override
  Future<LibraryItemsState> build() async => const LibraryItemsState(
    items: [
      MediaItem(
        id: 'series-bg',
        name: 'Circus Troupe',
        type: MediaType.series,
        poster: MediaImageResource(
          urlTemplate: 'http://127.0.0.1:8096/Items/series-bg/Images/Primary?maxWidth={width}&tag=poster-tag-1',
          cacheKey: 'series-bg:poster-tag-1',
        ),
      ),
    ],
    totalRecordCount: 1,
  );
}
