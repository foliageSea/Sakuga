import 'dart:async';
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
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/home/home_page.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';
import 'package:sakuga/shared/media_widgets.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/widgets.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

MediaItem _resumableEpisode({bool played = false}) => MediaItem(
  id: 'episode-1',
  name: 'Pilot',
  type: MediaType.episode,
  seriesId: 'series-1',
  seriesName: 'Resumed Series',
  seasonId: 'season-1',
  indexNumber: 1,
  parentIndexNumber: 1,
  reportedPlayedPercentage: 42.0,
  played: played,
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
  bool useClientCarousel = false,
  List<MediaItem>? resume,
  List<MediaItem>? latest,
  FakeMediaServerClient? client,
  Future<List<MediaItem>> Function()? loadResume,
  PlaybackProgressRepository? progress,
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
      if (progress != null)
        playbackProgressRepositoryProvider.overrideWithValue(progress),
      serverRepositoryProvider.overrideWithValue(servers),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: client ?? FakeMediaServerClient(server: _server),
          userId: 'user-1',
          views: const [],
        ),
      ),
      if (!useClientCarousel)
        randomItemsProvider.overrideWith(
          (ref) async => carousel ?? const <MediaItem>[],
        ),
      resumeItemsProvider.overrideWith(
        (ref) async => loadResume != null
            ? await loadResume()
            : resume ?? [_resumableEpisode()],
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

class _PlayedClient extends FakeMediaServerClient {
  _PlayedClient() : super(server: _server);
  final calls = <(String, String, bool)>[];
  bool played = false;
  Object? error;
  Completer<void>? pending;

  @override
  Future<void> setPlayed(
    String userId,
    String itemId, {
    required bool played,
  }) async {
    calls.add((userId, itemId, played));
    if (error != null) throw error!;
    await pending?.future;
    this.played = played;
  }

  Future<List<MediaItem>> resumeItems() async =>
      played ? [] : [_resumableEpisode()];
}

class _NoProgress extends Fake implements PlaybackProgressRepository {
  @override
  Future<int?> load({
    required String serverId,
    required String userId,
    required String itemId,
  }) async => null;
}

class _UgreenCarouselClient extends FakeMediaServerClient {
  _UgreenCarouselClient()
    : super(
        server: const ServerProfile(
          id: 'ugreen-test',
          name: 'UGREEN',
          baseUrl: 'https://nas.test:9443',
          type: MediaServerType.ugreen,
          userId: 'user-1',
          accessToken: 'test-token',
        ),
      );

  @override
  Future<List<MediaItem>> randomItems(
    String userId, {
    int limit = 8,
  }) async => const [
    MediaItem(id: 'ugreen-pick', name: 'UGREEN Pick', type: MediaType.series),
  ];
}

void main() {
  testWidgets('UGREEN renders its carousel picks and opens the series', (
    tester,
  ) async {
    await pumpHome(
      tester,
      client: _UgreenCarouselClient(),
      useClientCarousel: true,
    );
    expect(find.byKey(const ValueKey('home-poster-carousel')), findsOneWidget);
    await _tapCard(tester, 'UGREEN Pick');
    expect(find.text('detail:ugreen-pick'), findsOneWidget);
  });

  testWidgets('resume movie and episode cards keep equal heights', (
    tester,
  ) async {
    const movie = MediaItem(
      id: 'resume-movie',
      name: 'Resumed Movie',
      type: MediaType.movie,
      reportedPlayedPercentage: 20,
    );
    const noProgressMovie = MediaItem(
      id: 'resume-no-progress',
      name: 'Movie without progress',
      type: MediaType.movie,
    );
    await pumpHome(
      tester,
      resume: [movie, _resumableEpisode(), noProgressMovie],
      latest: const [],
    );

    final cards = find.byType(MediaPosterCard);
    expect(cards, findsNWidgets(3));
    final movieRect = tester.getRect(cards.at(0));
    final episodeRect = tester.getRect(cards.at(1));
    final noProgressRect = tester.getRect(cards.at(2));
    expect(movieRect.top, episodeRect.top);
    expect(movieRect.bottom, episodeRect.bottom);
    expect(noProgressRect.height, movieRect.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already played resume items can be marked played again', (
    tester,
  ) async {
    final client = _PlayedClient();
    await pumpHome(
      tester,
      client: client,
      resume: [_resumableEpisode(played: true)],
      progress: _NoProgress(),
    );
    final button = find.byKey(const ValueKey('played-status-episode-1'));
    expect(button, findsOneWidget);
    expect(find.bySemanticsLabel('Pilot: Mark as played'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.undo2), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(client.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('played-status-confirm')));
    await tester.pumpAndSettle();
    expect(client.calls, [('user-1', 'episode-1', true)]);
    expect(find.bySemanticsLabel('Pilot: Mark as played'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.undo2), findsNothing);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'resume poster ghost action marks played without navigating at $width',
      (tester) async {
        final client = _PlayedClient();
        await pumpHome(
          tester,
          client: client,
          loadResume: client.resumeItems,
          progress: _NoProgress(),
          size: Size(width, 1200),
        );
        final button = find.byKey(const ValueKey('played-status-episode-1'));
        expect(button, findsOneWidget);
        expect(tester.widget<FButton>(button).variant, FButtonVariant.ghost);
        expect(find.bySemanticsLabel('Pilot: Mark as played'), findsOneWidget);
        final card = find.ancestor(
          of: button,
          matching: find.byType(MediaPosterCard),
        );
        final poster = find.descendant(
          of: card,
          matching: find.byType(PosterHero),
        );
        final bounds = tester.getRect(poster);
        final action = tester.getRect(button);
        expect(bounds.right - action.right, closeTo(6, 0.1));
        expect(bounds.bottom - action.bottom, closeTo(6, 0.1));
        expect(bounds.contains(action.center), isTrue);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(client.calls, isEmpty);
        expect(
          find.descendant(
            of: find.byType(FDialog),
            matching: find.text(
              'Mark “Resumed Series · S01E01 · Pilot” as played?',
            ),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('played-status-confirm')));
        await tester.pumpAndSettle();
        expect(client.calls, [('user-1', 'episode-1', true)]);
        expect(find.text('Resumed Series'), findsNothing);
        expect(find.text('player:episode-1'), findsNothing);
        expect(find.byType(HomePage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'busy resume poster button ignores repeated taps without starting playback',
    (tester) async {
      final client = _PlayedClient()..pending = Completer<void>();
      await pumpHome(
        tester,
        client: client,
        loadResume: client.resumeItems,
        progress: _NoProgress(),
      );
      final button = find.byKey(const ValueKey('played-status-episode-1'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('played-status-confirm')));
      await tester.pump();
      expect(tester.widget<FButton>(button).onPress, isNull);
      expect(
        find.descendant(of: button, matching: find.byType(FCircularProgress)),
        findsOneWidget,
      );
      await tester.tap(button);
      await tester.pump();
      expect(client.calls.length, 1);
      expect(find.byType(HomePage), findsOneWidget);
      client.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Resumed Series'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed poster action keeps the card and can retry', (
    tester,
  ) async {
    final client = _PlayedClient()
      ..error = const AppException(FailureKind.server);
    await pumpHome(
      tester,
      client: client,
      loadResume: client.resumeItems,
      progress: _NoProgress(),
    );
    final button = find.byKey(const ValueKey('played-status-episode-1'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('played-status-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Resumed Series'), findsOneWidget);
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(FLucideIcons.circleAlert),
      ),
      findsOneWidget,
    );
    expect(find.byType(HomePage), findsOneWidget);
    client.error = null;
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('played-status-confirm')));
    await tester.pumpAndSettle();
    expect(client.calls.length, 2);
    expect(find.text('Resumed Series'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (width, accountLogin) in [
    (390.0, false),
    (1280.0, false),
    (390.0, true),
    (1280.0, true),
  ]) {
    testWidgets(
      'home refresh reloads all sections at width $width (account: $accountLogin)',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String, int>{};
        Future<List<MediaItem>> load(String section) async {
          calls.update(section, (value) => value + 1, ifAbsent: () => 1);
          return [];
        }

        final server = accountLogin
            ? _server.copyWith(
                apiKey: '',
                accessToken: 'account-token',
                userId: 'user-1',
                username: 'Alice',
                deviceId: 'device',
              )
            : _server;
        final servers = MemoryServerRepository()..items = [server];
        final container = ProviderContainer(
          overrides: [
            initialSettingsProvider.overrideWithValue(
              const AppSettings(language: 'en'),
            ),
            settingsRepositoryProvider.overrideWithValue(MemorySettings()),
            desktopWindowProvider.overrideWithValue(
              FakeWindow(available: false),
            ),
            serverRepositoryProvider.overrideWithValue(servers),
            libraryViewsProvider.overrideWith(
              (ref) async => LibraryData(
                client: FakeMediaServerClient(server: server),
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
      },
    );
  }

  testWidgets('wide carousel slide mirrors the detail banner', (tester) async {
    await pumpHome(
      tester,
      carousel: const [
        MediaItem(
          id: 'featured',
          name: 'Featured Title',
          type: MediaType.series,
          overview: 'A featured synopsis.',
          communityRating: 8.4,
          productionYear: 2018,
          genres: ['Animation', 'Comedy'],
        ),
      ],
    );
    final slide = find.byKey(const ValueKey('home-carousel-slide-featured'));
    Finder inSlide(Finder finder) =>
        find.descendant(of: slide, matching: finder);
    expect(
      inSlide(
        find.byKey(const ValueKey('home-carousel-featured-banner-title')),
      ),
      findsOneWidget,
    );
    expect(
      inSlide(find.byKey(const ValueKey('detail-rating'))),
      findsOneWidget,
    );
    expect(inSlide(find.text('Animation · Comedy')), findsOneWidget);
    expect(inSlide(find.text('A featured synopsis.')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('phone carousel bleeds edge to edge at $width', (tester) async {
      await pumpHome(
        tester,
        size: Size(width, 844),
        carousel: [
          for (final item in _loopItems)
            MediaItem(
              id: item.id,
              name: item.name,
              type: item.type,
              productionYear: 2018,
              genres: const ['Animation'],
            ),
        ],
      );
      final page = find.byType(PageView);
      expect(tester.getRect(page).left, 0);
      expect(tester.getRect(page).width, width);
      final title = find.byKey(
        const ValueKey('home-carousel-loop-1-banner-title'),
      );
      expect(tester.getCenter(title).dx, closeTo(width / 2, 1));
      expect(find.byKey(const ValueKey('home-carousel-prev')), findsNothing);
      expect(find.byKey(const ValueKey('home-carousel-dot-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide carousel has no arrows and dots still select slides', (
    tester,
  ) async {
    await pumpHome(tester, carousel: _loopItems);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(find.byKey(const ValueKey('home-carousel-prev')), findsNothing);
    expect(find.byKey(const ValueKey('home-carousel-next')), findsNothing);
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

  for (final width in [390.0, 1280.0]) {
    testWidgets('recent cards use portrait series artwork at width $width', (
      tester,
    ) async {
      await pumpHome(
        tester,
        size: Size(width, 1200),
        resume: [],
        latest: const [
          MediaItem(
            id: 'portrait-episode',
            name: 'Portrait episode',
            type: MediaType.episode,
            primaryImageAspectRatio: 2 / 3,
            reportedPlayedPercentage: 42,
          ),
          MediaItem(
            id: 'landscape-episode',
            name: 'Landscape episode',
            type: MediaType.episode,
            primaryImageAspectRatio: 16 / 9,
            seriesPoster: MediaImageResource(
              urlTemplate: 'https://media.test/series-poster',
              cacheKey: 'series-poster',
            ),
          ),
          MediaItem(id: 'series', name: 'Series', type: MediaType.series),
        ],
      );
      final cards = find.byType(MediaPosterCard);
      expect(cards, findsNWidgets(3));
      final portrait = tester.getRect(cards.at(0));
      final landscape = tester.getRect(cards.at(1));
      final series = tester.getRect(cards.at(2));
      expect(portrait.width, 160);
      expect(landscape.width, 160);
      expect(series.width, 160);
      expect(landscape.top, portrait.top);
      expect(series.top, portrait.top);
      expect(portrait.height, lessThan(310));
      expect(landscape.height, lessThan(310));
      expect(series.height, lessThan(310));
      final episodeCard = cards.at(1);
      final artwork = tester.widget<MediaImage>(
        find.descendant(of: episodeCard, matching: find.byType(MediaImage)),
      );
      expect(artwork.url, 'https://media.test/series-poster');
      expect(tester.widget<MediaPosterCard>(episodeCard).aspectRatio, 2 / 3);
      expect(find.byType(MediaProgressBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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

  for (final mobile in [false, true]) {
    testWidgets(
      'home carousel extends under the ${mobile ? 'phone header' : 'title bar'} and matches detail artwork height',
      (tester) async {
        // Short windows so the page content scrolls under the chrome.
        final windowSize = mobile
            ? const Size(390, 560)
            : const Size(1280, 600);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = windowSize;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const featured = MediaItem(
          id: 'featured-1',
          name: 'Sunflower Circus',
          type: MediaType.series,
          poster: MediaImageResource(
            urlTemplate: 'http://127.0.0.1:8096/Items/featured-1/Images/Primary?maxWidth={width}',
            cacheKey: 'featured-1:poster',
          ),
          backdrop: MediaImageResource(
            urlTemplate: 'http://127.0.0.1:8096/Items/featured-1/Images/Backdrop/0?maxWidth={width}',
            cacheKey: 'featured-1:backdrop',
          ),
          overview: 'A troupe of performers travelling across Japan.',
        );
        final servers = MemoryServerRepository()..items = [_server];
        final container = ProviderContainer(
          overrides: [
            initialSettingsProvider.overrideWithValue(
              const AppSettings(language: 'en'),
            ),
            settingsRepositoryProvider.overrideWithValue(MemorySettings()),
            desktopWindowProvider.overrideWithValue(
              FakeWindow(available: !mobile, macOS: true),
            ),
            serverRepositoryProvider.overrideWithValue(servers),
            libraryViewsProvider.overrideWith(
              (ref) async => LibraryData(
                client: FakeMediaServerClient(server: _server),
                userId: 'user-1',
                views: const [],
              ),
            ),
            randomItemsProvider.overrideWith((ref) async => const [featured]),
            libraryItemProvider.overrideWith((ref, query) async => featured),
            seriesSeasonsProvider.overrideWith((ref, query) async => const []),
            seriesEpisodesProvider.overrideWith((ref, query) async => const []),
            resumeItemsProvider.overrideWith(
              (ref) async => [
                for (var i = 0; i < 8; i++)
                  MediaItem(
                    id: 'resume-$i',
                    name: 'Resume $i',
                    type: MediaType.movie,
                  ),
              ],
            ),
            latestItemsProvider.overrideWith((ref) async => const []),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SakugaApp(),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        final carousel = find.byKey(const ValueKey('home-poster-carousel'));
        final page = find.byType(PageView);
        final homeArt = mobile
            ? find.byKey(const ValueKey('home-carousel-mobile-art'))
            : page;
        final artworkHeight = tester.getSize(homeArt).height;
        expect(tester.getRect(page).top, 0);
        if (mobile) {
          final header = find.byKey(const ValueKey('mobile-header'));
          expect(tester.getRect(header).top, 0);
          expect(tester.getRect(page).left, 0);
          expect(tester.getRect(page).width, windowSize.width);
        } else {
          expect(tester.getRect(find.byType(DesktopTitleBar)).top, 0);
          expect(
            find.descendant(
              of: find.byType(DesktopTitleBar),
              matching: find.byKey(const ValueKey('home-refresh')),
            ),
            findsOneWidget,
          );
          expect(find.text('Home'), findsNothing);
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('sidebar-logo'))).dy,
            greaterThan(48),
          );
        }
        expect(find.byKey(const ValueKey('home-refresh')), findsOneWidget);

        double backing() => tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('immersive-chrome-backing')),
            )
            .opacity;
        expect(backing(), 0);
        await tester.drag(carousel, const Offset(0, -300));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(backing(), 1);

        container.read(routerProvider).go('/library/${featured.id}');
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final detailArt = find.byKey(
          ValueKey(mobile ? 'detail-mobile-art' : 'detail-desktop-art'),
        );
        expect(tester.getSize(detailArt).height, artworkHeight);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

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
      expect(
        find.descendant(
          of: find.byType(HomePage),
          matching: find.text('Test server'),
        ),
        findsNothing,
      );
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

      // Selecting the first dot returns to the first slide.
      expect(find.byKey(const ValueKey('home-carousel-prev')), findsNothing);
      expect(find.byKey(const ValueKey('home-carousel-next')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-carousel-dot-0')));
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
