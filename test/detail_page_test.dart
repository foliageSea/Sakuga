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
MediaItem _movie({Duration? position}) => MediaItem(
  id: 'movie-1',
  name: _title,
  type: MediaType.movie,
  runtime: const Duration(minutes: 97),
  playbackPosition: position,
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

MediaItem _season() => const MediaItem(
  id: 'season-1',
  name: 'Season 1',
  type: MediaType.season,
  seriesId: 'series-1',
  seriesName: 'A Series With Episodes',
  indexNumber: 1,
  childCount: 13,
);

MediaItem _seasonTwo() => const MediaItem(
  id: 'season-2',
  name: 'Season 2',
  type: MediaType.season,
  seriesId: 'series-1',
  seriesName: 'A Series With Episodes',
  indexNumber: 2,
  childCount: 12,
);

MediaItem _episode() => const MediaItem(
  id: 'episode-1',
  name: 'Pilot',
  type: MediaType.episode,
  seriesId: 'series-1',
  seriesName: 'A Series With Episodes',
  seasonId: 'season-1',
  indexNumber: 1,
  parentIndexNumber: 1,
  runtime: Duration(minutes: 24),
  overview: 'The troupe arrives in a new town for its first performance.',
);

/// Pumps the real detail route behind a router so the back button can pop.
Future<GoRouter> pumpDetailPage(
  WidgetTester tester, {
  required FutureOr<MediaItem> Function() item,
  Size size = const Size(1280, 800),
  bool settle = true,
  bool withPlayerRoute = false,
  ServerProfile server = _server,
  List<MediaItem>? seasons,
  List<MediaItem>? episodes,
  FutureOr<MediaItem> Function(String id)? itemById,
  FutureOr<List<MediaItem>> Function(SeriesQuery query)? loadSeasons,
  FutureOr<List<MediaItem>> Function(EpisodesQuery query)? loadEpisodes,
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
            pageBuilder: (_, state) => buildDetailTransitionPage(state),
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
    retry: (_, _) => null,
    overrides: [
      if (seasons != null || loadSeasons != null)
        seriesSeasonsProvider.overrideWith(
          (ref, query) => loadSeasons?.call(query) ?? seasons!,
        ),
      if (episodes != null || loadEpisodes != null)
        seriesEpisodesProvider.overrideWith(
          (ref, query) => loadEpisodes?.call(query) ?? episodes!,
        ),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: FakeMediaServerClient(server: server),
          userId: 'user-1',
          views: const [],
        ),
      ),
      libraryItemProvider.overrideWith(
        (ref, query) => itemById?.call(query.itemId) ?? item(),
      ),
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

/// The vertical page scrollable, excluding nested horizontal strips.
Finder get _pageScrollable => find
    .descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    )
    .first;

ScrollPosition _pageScrollPosition(WidgetTester tester) =>
    tester.state<ScrollableState>(_pageScrollable).position;

/// Scrolls the page by [dy] and checks that the back button kept its place
/// and title while the page content moved.
Future<void> expectBackButtonPinned(
  WidgetTester tester, {
  double dy = -320,
}) async {
  expect(_backButton, findsOneWidget);
  final pinnedAt = tester.getTopLeft(_backButton);
  final headerTitle = find.byKey(const ValueKey('detail-title'));
  final titleBefore = tester.getTopLeft(headerTitle);
  final contentBefore = tester.getTopLeft(find.text('PG-13')).dy;

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
    tester.getTopLeft(find.text('PG-13')).dy,
    lessThan(contentBefore),
    reason: 'the content should scroll under the pinned back button',
  );
  expect(tester.getTopLeft(_backButton), pinnedAt);
  expect(tester.getTopLeft(headerTitle), titleBefore);
}

void main() {
  for (final type in MediaServerType.values) {
    testWidgets('${type.name} movie plays from the banner above the credits', (
      tester,
    ) async {
      await pumpDetailPage(
        tester,
        server: _server.copyWith(type: type),
        item: _movie,
        size: Size(type == MediaServerType.ugreen ? 320 : 1280, 900),
        withPlayerRoute: true,
      );
      final play = find.byKey(const ValueKey('detail-play'));
      final credits = find.byKey(const ValueKey('detail-about'));
      expect(play.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(play).dy,
        lessThan(tester.getTopLeft(credits).dy),
      );
      expect(find.byKey(const ValueKey('detail-banner-title')), findsOneWidget);
      expect(find.text('97 min'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('detail-overview-more')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('detail-movie-movie-1')), findsNothing);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(find.text('player:movie-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('movie with progress offers to continue watching', (
    tester,
  ) async {
    await pumpDetailPage(
      tester,
      item: () => _movie(position: const Duration(minutes: 20)),
    );
    expect(find.text('Continue watching'), findsOneWidget);
  });

  testWidgets(
    'UGREEN season card loads episodes without fetching season again',
    (tester) async {
      final pending = Completer<List<MediaItem>>();
      final requests = <EpisodesQuery>[];
      var duplicateSeasonLookups = 0;
      final router = await pumpDetailPage(
        tester,
        server: _server.copyWith(type: MediaServerType.ugreen),
        item: _series,
        itemById: (id) {
          if (id == _season().id) duplicateSeasonLookups++;
          if (id == _season().id) return _season();
          return _series();
        },
        loadEpisodes: (query) {
          requests.add(query);
          return pending.future;
        },
      );
      router.push(
        '/library/${_season().id}',
        extra: DetailRouteExtra(item: _season()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(requests, [
        (userId: 'user-1', seriesId: 'series-1', seasonId: 'season-1'),
      ]);
      pending.complete([_episode()]);
      await tester.pumpAndSettle();
      expect(duplicateSeasonLookups, 0);
      expect(find.text('1. Pilot'), findsOneWidget);
      expect(find.byType(LoadingNotice), findsNothing);
    },
  );

  for (final width in [820.0, 1280.0]) {
    testWidgets('season can return directly to library at width $width', (
      tester,
    ) async {
      final router = await pumpDetailPage(
        tester,
        item: _series,
        size: Size(width, 1000),
        seasons: [_season(), _seasonTwo()],
        episodes: [],
        itemById: (id) => id == 'season-1' ? _season() : _series(),
      );
      expect(
        find.byKey(const ValueKey('detail-back-to-library')),
        findsNothing,
      );
      final season = find.byKey(const ValueKey('detail-season-season-1'));
      await tester.ensureVisible(season);
      await tester.tap(season);
      await tester.pumpAndSettle();
      expect(router.canPop(), isTrue);
      final libraryButton = find.byKey(
        const ValueKey('detail-back-to-library'),
      );
      expect(libraryButton.hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('Back to library'), findsOneWidget);
      await tester.tap(libraryButton);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/library');
      expect(router.canPop(), isFalse);
      expect(find.byType(DetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(820, 1000), const Size(1280, 1000)]) {
    testWidgets(
      'cancelling a season push restores the series scroll and poster at ${size.width}',
      (tester) async {
        final seasonData = Completer<MediaItem>();
        final router = await pumpDetailPage(
          tester,
          item: _series,
          size: size,
          itemById: (id) => id == 'season-1' ? seasonData.future : _series(),
          seasons: [_season(), _seasonTwo()],
          episodes: const [],
        );
        final season = find.byKey(const ValueKey('detail-season-season-1'));
        await tester.ensureVisible(season);
        await tester.pumpAndSettle();
        final sourceScroll = Scrollable.of(tester.element(season)).position;
        final sourceOffset = sourceScroll.pixels;
        final sourceRect = tester.getRect(season);
        await tester.tap(season);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        router.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        seasonData.complete(_season());
        await tester.pumpAndSettle();
        expect(find.text('Season 1'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('detail-episode-episode-1')),
          findsNothing,
        );
        expect(
          Scrollable.of(tester.element(season)).position,
          same(sourceScroll),
        );
        expect(sourceScroll.pixels, sourceOffset);
        expect(tester.getRect(season), sourceRect);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(820, 1000), const Size(1280, 1000)]) {
    testWidgets(
      'season banner falls back to the season title without a logo at ${size.width}',
      (tester) async {
        final seasonData = Completer<MediaItem>();
        await pumpDetailPage(
          tester,
          item: _series,
          size: size,
          itemById: (id) => id == 'season-1' ? seasonData.future : _series(),
          seasons: [_season(), _seasonTwo()],
          episodes: const [],
        );
        final season = find.byKey(const ValueKey('detail-season-season-1'));
        await tester.ensureVisible(season);
        await tester.tap(season);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final seriesHeading = find.byKey(const ValueKey('detail-series-name'));
        expect(seriesHeading, findsNothing);
        expect(find.byKey(const ValueKey('detail-title')), findsOneWidget);
        seasonData.complete(
          const MediaItem(
            id: 'season-1',
            name: '',
            type: MediaType.season,
            seriesId: 'series-1',
            indexNumber: 1,
          ),
        );
        await tester.pumpAndSettle();
        final bannerTitle = find.byKey(const ValueKey('detail-banner-title'));
        expect(tester.widget<Text>(bannerTitle).data, 'Season 1');
        expect(find.byKey(const ValueKey('detail-logo')), findsNothing);
        expect(seriesHeading, findsNothing);
        expect(find.byKey(const ValueKey('detail-title')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(820, 1000), const Size(1280, 1000)]) {
    testWidgets(
      'season transition fades out the previous detail and restores it on return at ${size.width}',
      (tester) async {
        final seasonData = Completer<MediaItem>();
        final router = await pumpDetailPage(
          tester,
          item: _series,
          size: size,
          itemById: (id) => id == 'season-1' ? seasonData.future : _series(),
          seasons: [_season(), _seasonTwo()],
          episodes: [_episode()],
        );
        double routeOpacity(String id) {
          final page = find.byWidgetPredicate(
            (widget) => widget is DetailPage && widget.itemId == id,
            skipOffstage: false,
          );
          final fades = find.ancestor(
            of: page,
            matching: find.byType(FadeTransition, skipOffstage: false),
          );
          return tester
              .widgetList<FadeTransition>(fades)
              .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);
        }

        expect(routeOpacity('movie-1'), 1);
        final season = find.byKey(const ValueKey('detail-season-season-1'));
        await tester.ensureVisible(season);
        await tester.tap(season);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        final outgoingOpacity = routeOpacity('movie-1');
        expect(
          outgoingOpacity,
          inExclusiveRange(0, 0.5),
          reason: 'the old transparent detail must fade away under the incoming season',
        );
        expect(routeOpacity('season-1'), inExclusiveRange(0.5, 1));
        seasonData.complete(_season());
        await tester.pumpAndSettle();
        expect(routeOpacity('movie-1'), 0);
        router.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(routeOpacity('movie-1'), inExclusiveRange(0, 1));
        expect(routeOpacity('season-1'), inExclusiveRange(0, 1));
        await tester.pumpAndSettle();
        expect(routeOpacity('movie-1'), 1);
        expect(
          find.byKey(const ValueKey('detail-season-season-1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(700, 1000), const Size(1280, 1000)]) {
    testWidgets('season card opens numbered episode details at ${size.width}', (
      tester,
    ) async {
      final queries = <EpisodesQuery>[];
      await pumpDetailPage(
        tester,
        item: _series,
        size: size,
        withPlayerRoute: true,
        itemById: (id) => id == 'season-1' ? _season() : _series(),
        seasons: [_season(), _seasonTwo()],
        loadEpisodes: (query) {
          queries.add(query);
          return [_episode()];
        },
      );
      final season = find.byKey(const ValueKey('detail-season-season-1'));
      expect(season, findsOneWidget);
      final card = tester.widget<MediaPosterCard>(season);
      expect(card.framed, isTrue);
      expect(card.textAlign, TextAlign.start);
      expect(card.subtitle, '13 episodes');
      final surface = find.descendant(
        of: season,
        matching: find.byType(Surface),
      );
      expect(surface, findsOneWidget);
      expect(
        find.descendant(of: surface, matching: find.text('Season 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: surface, matching: find.text('13 episodes')),
        findsOneWidget,
      );
      expect(find.text('13 episodes'), findsOneWidget);
      expect(queries, isEmpty);
      await tester.ensureVisible(season);
      await tester.tap(season);
      await tester.pumpAndSettle();
      expect(queries, [
        (userId: 'user-1', seriesId: 'series-1', seasonId: 'season-1'),
      ]);
      final headerTitle = find.byKey(const ValueKey('detail-title'));
      expect(tester.widget<Text>(headerTitle).data, 'Season 1');
      expect(find.byKey(const ValueKey('detail-series-name')), findsNothing);
      final episode = find.byKey(const ValueKey('detail-episode-episode-1'));
      await tester.ensureVisible(episode);
      await tester.pumpAndSettle();
      expect(find.text('1. Pilot'), findsOneWidget);
      expect(find.text('00:24:00'), findsOneWidget);
      expect(find.text(_episode().overview!), findsOneWidget);
      await tester.tap(episode);
      await tester.pumpAndSettle();
      expect(find.text('player:episode-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'detail shows a valid rating on movie and series metadata at ${size.width}',
      (tester) async {
        await pumpDetailPage(
          tester,
          size: size,
          seasons: const [],
          episodes: const [],
          item: () => MediaItem(
            id: 'movie-1',
            name: 'Rated title',
            type: size.width < 1000 ? MediaType.movie : MediaType.series,
            communityRating: 8.6,
          ),
        );
        final rating = find.byKey(const ValueKey('detail-rating'));
        expect(rating, findsOneWidget);
        expect(
          find.descendant(of: rating, matching: find.text('8.6')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: rating, matching: find.byIcon(FLucideIcons.star)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'seasons and specials open their own episodes and back returns to the series',
    (tester) async {
      const secondSeason = MediaItem(
        id: 'season-2',
        name: 'Season 2',
        type: MediaType.season,
        seriesId: 'series-1',
        indexNumber: 2,
        childCount: 8,
      );
      const specials = MediaItem(
        id: 'specials',
        name: '',
        type: MediaType.season,
        seriesId: 'series-1',
        indexNumber: 0,
        childCount: 2,
      );
      final queries = <EpisodesQuery>[];
      await pumpDetailPage(
        tester,
        item: _series,
        size: const Size(1280, 1000),
        seasons: [specials, _season(), secondSeason],
        itemById: (id) => switch (id) {
          'season-2' => secondSeason,
          'specials' => specials,
          'season-1' => _season(),
          _ => _series(),
        },
        loadEpisodes: (query) {
          queries.add(query);
          return [
            MediaItem(
              id: 'episode-${query.seasonId}',
              name: 'From ${query.seasonId}',
              type: MediaType.episode,
              indexNumber: 1,
            ),
          ];
        },
      );
      expect(find.text('Specials'), findsOneWidget);
      for (final id in ['season-2', 'specials', 'season-1']) {
        final season = find.byKey(ValueKey('detail-season-$id'));
        await tester.ensureVisible(season);
        await tester.tap(season);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('detail-title'))).data,
          id == 'specials'
              ? 'Specials'
              : id == 'season-2'
              ? 'Season 2'
              : 'Season 1',
        );
        expect(queries.last.seasonId, id);
        expect(queries.last.seriesId, 'series-1');
        expect(find.text('1. From $id'), findsOneWidget);
        await tester.tap(_backButton);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('detail-season-season-1')),
          findsOneWidget,
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('detail-title'))).data,
          _series().name,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'season requests can retry and do not silently flatten the series',
    (tester) async {
      var attempts = 0;
      var episodeRequests = 0;
      await pumpDetailPage(
        tester,
        item: _series,
        size: const Size(1280, 1000),
        loadSeasons: (_) {
          attempts++;
          if (attempts == 1) throw const AppException(FailureKind.network);
          return [_season(), _seasonTwo()];
        },
        loadEpisodes: (_) {
          episodeRequests++;
          return [_episode()];
        },
      );
      expect(find.byType(ErrorNotice), findsOneWidget);
      expect(episodeRequests, 0);
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        find.byKey(const ValueKey('detail-season-season-1')),
        findsOneWidget,
      );
      expect(episodeRequests, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('series without season records can still play its episodes', (
    tester,
  ) async {
    final queries = <EpisodesQuery>[];
    await pumpDetailPage(
      tester,
      item: _series,
      size: const Size(1280, 1000),
      seasons: const [],
      loadEpisodes: (query) {
        queries.add(query);
        return [_episode()];
      },
    );
    expect(queries.single.seasonId, isNull);
    expect(find.text('1. Pilot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing episode metadata has no invented duration or summary', (
    tester,
  ) async {
    await pumpDetailPage(
      tester,
      item: _season,
      size: const Size(320, 760),
      episodes: const [
        MediaItem(id: 'plain', name: 'Plain episode', type: MediaType.episode),
      ],
    );
    final tile = find.byKey(const ValueKey('detail-episode-plain'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(find.text('Plain episode'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-episode-metadata-plain')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('detail-episode-overview-plain')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('detail-rating')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late episode response from a previous season cannot replace the current season',
    (tester) async {
      final lateEpisodes = Completer<List<MediaItem>>();
      const secondSeason = MediaItem(
        id: 'season-2',
        name: 'Season 2',
        type: MediaType.season,
        seriesId: 'series-1',
      );
      await pumpDetailPage(
        tester,
        item: _series,
        size: const Size(1280, 1000),
        seasons: [_season(), secondSeason],
        itemById: (id) => id == 'season-1'
            ? _season()
            : id == 'season-2'
            ? secondSeason
            : _series(),
        loadEpisodes: (query) => query.seasonId == 'season-1'
            ? lateEpisodes.future
            : const [
                MediaItem(
                  id: 'current',
                  name: 'Current season episode',
                  type: MediaType.episode,
                  indexNumber: 1,
                ),
              ],
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('detail-season-season-1')),
      );
      await tester.tap(find.byKey(const ValueKey('detail-season-season-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_backButton);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('detail-season-season-2')),
      );
      await tester.tap(find.byKey(const ValueKey('detail-season-season-2')));
      await tester.pumpAndSettle();
      lateEpisodes.complete([_episode()]);
      await tester.pumpAndSettle();
      expect(find.text('1. Current season episode'), findsOneWidget);
      expect(find.text('1. Pilot'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets(
      'series banner shows its title without a logo at width ${size.width}',
      (tester) async {
        final series = _series();
        await pumpDetailPage(
          tester,
          size: size,
          item: () => series,
          seasons: const [],
          episodes: const [],
        );

        final bannerTitle = find.byKey(const ValueKey('detail-banner-title'));
        expect(tester.widget<Text>(bannerTitle).data, series.name);
        expect(find.byKey(const ValueKey('detail-logo')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'detail uses header title and banner logo at width ${size.width}',
      (tester) async {
        await pumpDetailPage(
          tester,
          size: size,
          item: () => const MediaItem(
            id: 'series-1',
            name: _title,
            type: MediaType.series,
            logo: MediaImageResource(
              urlTemplate: 'http://127.0.0.1:8096/Items/series-1/Images/Logo?maxWidth={width}',
              cacheKey: 'series-logo',
              headers: {'X-Emby-Token': 'test-key'},
            ),
          ),
          seasons: const [],
          episodes: const [],
        );

        final headerTitle = find.byKey(const ValueKey('detail-title'));
        expect(tester.widget<Text>(headerTitle).data, _title);
        final logoFinder = find.byKey(const ValueKey('detail-logo'));
        final logo = tester.widget<CachedNetworkImage>(logoFinder);
        expect(logo.imageUrl, contains('Images/Logo?maxWidth=840'));
        expect(logo.httpHeaders, {'X-Emby-Token': 'test-key'});
        expect(logo.fit, BoxFit.contain);
        final fallback = logo.errorWidget!(
          tester.element(logoFinder),
          logo.imageUrl,
          StateError('Logo unavailable'),
        );
        expect(((fallback as Align).child! as Text).data, _title);
        expect(
          tester.getRect(headerTitle).bottom,
          lessThan(tester.getRect(logoFinder).top),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('series and season redesign', () {
    MediaItem ep(int n, {bool played = false, Duration? position}) => MediaItem(
      id: 'episode-$n',
      name: 'Episode name $n',
      type: MediaType.episode,
      seriesId: 'series-1',
      seasonId: 'season-1',
      indexNumber: n,
      parentIndexNumber: 1,
      runtime: const Duration(minutes: 13, seconds: 29),
      played: played,
      playbackPosition: position,
      overview: 'Overview $n',
    );

    for (final size in [const Size(390, 844), const Size(1280, 800)]) {
      testWidgets('season play opens the next episode at ${size.width}', (
        tester,
      ) async {
        await pumpDetailPage(
          tester,
          size: size,
          withPlayerRoute: true,
          item: () => _season().copyForTest(overview: 'Season synopsis.'),
          episodes: [ep(1, played: true), ep(2), ep(3)],
        );
        final play = find.byKey(const ValueKey('detail-play'));
        expect(
          find.descendant(of: play, matching: find.text('Episode 2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('detail-episode-next-episode-2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('detail-episode-duration-episode-1')),
          findsOneWidget,
        );
        expect(find.text('00:13:29'), findsNWidgets(3));
        await tester.tap(play);
        await tester.pumpAndSettle();
        expect(find.text('player:episode-2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'episode thumbnails stay in one scrollable row at ${size.width}',
        (tester) async {
          await pumpDetailPage(
            tester,
            size: size,
            item: _season,
            episodes: [for (var i = 1; i <= 8; i++) ep(i)],
          );
          final row = find.byKey(const ValueKey('detail-episodes-row'));
          Finder card(int n) =>
              find.byKey(ValueKey('detail-episode-episode-$n'));
          await tester.ensureVisible(card(1));
          await tester.pumpAndSettle();
          final first = tester.getTopLeft(card(1));
          final last = tester.getTopLeft(card(8));
          expect(last.dy, first.dy);
          expect(last.dx, greaterThan(tester.getRect(row).right));
          expect(
            find.byKey(const ValueKey('detail-episode-title-episode-1')),
            findsOneWidget,
          );
          expect(find.text('8 episodes'), findsOneWidget);
          for (final key in ['toggle', 'row-view', 'grid-view']) {
            expect(find.byKey(ValueKey('detail-episodes-$key')), findsNothing);
          }
          await tester.drag(row, const Offset(-160, 0));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(card(1)).dx, lessThan(first.dx));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final width in [320.0, 390.0, 480.0]) {
      testWidgets('mobile season header fits the viewport at $width', (
        tester,
      ) async {
        await pumpDetailPage(
          tester,
          size: Size(width, 844),
          item: () => const MediaItem(
            id: 'season-1',
            name: 'Season 2',
            type: MediaType.season,
            seriesId: 'series-1',
            indexNumber: 2,
            childCount: 24,
            communityRating: 8.4,
            productionYear: 2014,
            genres: ['Drama', 'Animation', 'Comedy'],
            overview: 'A short synopsis.',
            logo: MediaImageResource(
              urlTemplate:
                  'http://127.0.0.1:8096/Items/s/Images/Logo?maxWidth={width}',
              cacheKey: 'season-logo',
            ),
          ),
          episodes: [for (var i = 1; i <= 6; i++) ep(i)],
        );
        final logo = tester.getRect(find.byKey(const ValueKey('detail-logo')));
        expect(logo.right, lessThanOrEqualTo(width));
        expect(logo.height, lessThanOrEqualTo(80));
        final play = tester.getRect(find.byKey(const ValueKey('detail-play')));
        expect(play.bottom, lessThan(844 * 0.75));
        final row = find.byKey(const ValueKey('detail-episodes-row'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final first = tester.getRect(
          find.byKey(const ValueKey('detail-episode-episode-1')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('detail-episode-episode-2')),
        );
        expect(first.right, lessThan(tester.getRect(row).right));
        expect(second.top, first.top);
        expect(second.left, greaterThan(first.right));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('phone series switches seasons with tabs', (tester) async {
      final queries = <EpisodesQuery>[];
      const specials = MediaItem(
        id: 'specials',
        name: '',
        type: MediaType.season,
        seriesId: 'series-1',
        indexNumber: 0,
      );
      await pumpDetailPage(
        tester,
        size: const Size(390, 844),
        item: () => _series().copyForTest(people: _movie().people),
        seasons: [specials, _season(), _seasonTwo()],
        loadEpisodes: (query) {
          queries.add(query);
          return [
            for (var i = 1; i <= 3; i++)
              MediaItem(
                id: '${query.seasonId}-$i',
                name: 'Episode $i',
                type: MediaType.episode,
                indexNumber: i,
              ),
          ];
        },
      );
      expect(
        find.byKey(const ValueKey('detail-season-season-1')),
        findsNothing,
      );
      expect(queries.last.seasonId, 'season-1');
      expect(
        find.byKey(const ValueKey('detail-episode-season-1-1')),
        findsOneWidget,
      );
      final tab = find.byKey(const ValueKey('detail-season-tab-season-2'));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(queries.last.seasonId, 'season-2');
      expect(
        find.byKey(const ValueKey('detail-episode-season-2-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('detail-episode-season-1-1')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('detail-cast')),
        300,
        scrollable: _pageScrollable,
      );
      expect(find.text('Person 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resumed season episode labels the play button', (
      tester,
    ) async {
      await pumpDetailPage(
        tester,
        item: _season,
        episodes: [
          ep(1, played: true),
          ep(2, position: const Duration(minutes: 3)),
        ],
      );
      expect(find.text('Resume episode 2'), findsOneWidget);
    });

    testWidgets('series play loads episodes only when pressed', (tester) async {
      final queries = <EpisodesQuery>[];
      await pumpDetailPage(
        tester,
        withPlayerRoute: true,
        item: _series,
        seasons: [_season(), _seasonTwo()],
        loadEpisodes: (query) {
          queries.add(query);
          return [ep(1, played: true), ep(2)];
        },
      );
      expect(queries, isEmpty);
      await tester.tap(find.byKey(const ValueKey('detail-play')));
      await tester.pumpAndSettle();
      expect(queries, [
        (userId: 'user-1', seriesId: 'series-1', seasonId: null),
      ]);
      expect(find.text('player:episode-2'), findsOneWidget);
    });

    testWidgets('long synopsis opens in a dialog', (tester) async {
      final long = List.filled(40, 'A long mountain synopsis.').join(' ');
      await pumpDetailPage(
        tester,
        item: () => _series().copyForTest(overview: long),
        seasons: [_season(), _seasonTwo()],
      );
      final more = find.byKey(const ValueKey('detail-overview-more'));
      expect(more, findsOneWidget);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('detail-overview-full')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('detail-overview-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('detail-overview-full')), findsNothing);
    });

    testWidgets('short synopsis has no more action', (tester) async {
      await pumpDetailPage(
        tester,
        item: _series,
        seasons: [_season(), _seasonTwo()],
      );
      expect(find.byKey(const ValueKey('detail-overview')), findsOneWidget);
      expect(find.byKey(const ValueKey('detail-overview-more')), findsNothing);
      expect(find.text('Synopsis'), findsNothing);
    });

    testWidgets('season selection hides cast and studios', (tester) async {
      await pumpDetailPage(
        tester,
        size: const Size(1280, 1400),
        item: () => _series().copyForTest(people: _movie().people),
        seasons: [_season(), _seasonTwo()],
      );
      expect(
        find.byKey(const ValueKey('detail-season-season-1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('detail-about')), findsNothing);
      expect(find.text('Person 0'), findsNothing);
    });

    for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
      testWidgets(
        'a single-season series lists its episodes directly at ${size.width}',
        (tester) async {
          final queries = <EpisodesQuery>[];
          await pumpDetailPage(
            tester,
            size: size,
            withPlayerRoute: true,
            item: () => _series().copyForTest(people: _movie().people),
            seasons: [_season()],
            loadEpisodes: (query) {
              queries.add(query);
              return [ep(1, played: true), ep(2)];
            },
          );
          expect(
            find.byKey(const ValueKey('detail-season-season-1')),
            findsNothing,
          );
          expect(queries, [
            (userId: 'user-1', seriesId: 'series-1', seasonId: 'season-1'),
          ]);
          expect(
            find.byKey(const ValueKey('detail-episode-episode-2')),
            findsOneWidget,
          );
          final play = find.byKey(const ValueKey('detail-play'));
          expect(
            find.descendant(of: play, matching: find.text('Episode 2')),
            findsOneWidget,
          );
          final about = find.byKey(const ValueKey('detail-about'));
          await tester.scrollUntilVisible(
            about,
            300,
            scrollable: _pageScrollable,
          );
          await tester.pumpAndSettle();
          expect(
            tester.getTopLeft(about).dy,
            greaterThan(
              tester
                  .getTopLeft(
                    find.byKey(const ValueKey('detail-episode-episode-1')),
                  )
                  .dy,
            ),
          );
          await tester.scrollUntilVisible(
            play,
            -300,
            scrollable: _pageScrollable,
          );
          await tester.pumpAndSettle();
          await tester.tap(play);
          await tester.pumpAndSettle();
          expect(find.text('player:episode-2'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

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
      itemById: (id) => id == 'season-1' ? _season() : _series(),
      seasons: [_season(), _seasonTwo()],
      episodes: [episode],
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('detail-season-season-1')),
    );
    await tester.tap(find.byKey(const ValueKey('detail-season-season-1')));
    await tester.pumpAndSettle();
    final tile = find.byKey(ValueKey('detail-episode-${episode.id}'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
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
      item: _season,
      size: const Size(1280, 1000),
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

  testWidgets('mobile movie artwork extends under the safe area and AppBar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 560);
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);

    final movie = MediaItem(
      id: 'movie-1',
      name: _title,
      type: MediaType.movie,
      backdrop: const MediaImageResource(
        urlTemplate: 'http://127.0.0.1:8096/movie/backdrop?width={width}',
        cacheKey: 'movie-backdrop',
      ),
      people: _movie().people,
    );
    final servers = MemoryServerRepository()..items = [_server];
    final container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          const AppSettings(language: 'en'),
        ),
        settingsRepositoryProvider.overrideWithValue(MemorySettings()),
        desktopWindowProvider.overrideWithValue(FakeWindow()),
        serverRepositoryProvider.overrideWithValue(servers),
        libraryViewsProvider.overrideWith(
          (ref) async => LibraryData(
            client: FakeMediaServerClient(server: _server),
            userId: 'user-1',
            views: const [],
          ),
        ),
        libraryItemProvider.overrideWith((ref, query) async => movie),
        randomItemsProvider.overrideWith((ref) async => const []),
        resumeItemsProvider.overrideWith((ref) async => const []),
        latestItemsProvider.overrideWith((ref) async => const []),
      ],
    );
    addTearDown(container.dispose);
    container.read(routerProvider).go('/library/movie-1');
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('mobile-header'));
    final art = find.byKey(const ValueKey('detail-mobile-art'));
    expect(tester.getRect(art).topLeft, Offset.zero);
    expect(tester.getRect(art).width, 390);
    expect(tester.getRect(header).top, 24);
    expect(tester.getRect(header).bottom, lessThan(tester.getRect(art).bottom));
    final frosted = find.byKey(const ValueKey('immersive-chrome-backing'));
    expect(tester.widget<AnimatedOpacity>(frosted).opacity, 0);
    await tester.dragFrom(const Offset(200, 290), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(frosted).opacity, 1);
    expect(_backButton.hitTestable(), findsOneWidget);
    await tester.tap(_backButton);
    await tester.pumpAndSettle();
    expect(find.byType(DetailPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail page uses series poster as global window background with Gaussian blur mask',
    (tester) async {
      const windowSize = Size(1680, 900);
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
        ImageFilter.blur(sigmaX: 20, sigmaY: 20, tileMode: TileMode.clamp),
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
      final artwork = tester.getRect(
        find.byKey(const ValueKey('detail-desktop-art')),
      );
      final titleBar = tester.getRect(find.byType(DesktopTitleBar));
      final detailHeader = tester.getRect(
        find.byKey(const ValueKey('desktop-detail-header')),
      );
      expect(artwork.top, titleBar.top);
      expect(artwork.left, tester.getRect(find.byType(FSidebar)).right);
      expect(artwork.right, windowSize.width);
      expect(detailHeader.top, titleBar.bottom);
      expect(detailHeader.bottom, lessThan(artwork.bottom));
      expect(_backButton.hitTestable(), findsOneWidget);

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

extension on MediaItem {
  MediaItem copyForTest({String? overview, List<MediaPerson>? people}) =>
      MediaItem(
        id: id,
        name: name,
        type: type,
        seriesId: seriesId,
        seriesName: seriesName,
        indexNumber: indexNumber,
        childCount: childCount,
        genres: genres,
        productionYear: productionYear,
        overview: overview ?? this.overview,
        people: people ?? this.people,
      );
}
