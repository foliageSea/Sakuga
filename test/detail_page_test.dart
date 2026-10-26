import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_models.dart';
import 'package:sakuga/data/jellyfin/server_profile.dart';
import 'package:sakuga/features/detail/detail_page.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/widgets.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

const _title = 'A Long Movie Title For The Detail Page';

/// A movie tall enough that the detail page always scrolls, with no image tags
/// so the test never touches the network or the on-disk image cache.
JellyfinItem _movie() => JellyfinItem(
  id: 'movie-1',
  name: _title,
  type: 'Movie',
  imageTags: const {},
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
      JellyfinPerson(
        id: 'person-$i',
        name: 'Person $i',
        role: 'Role $i',
        type: 'Actor',
      ),
  ],
);

/// Pumps the real detail route behind a router so the back button can pop.
Future<GoRouter> pumpDetailPage(
  WidgetTester tester, {
  required FutureOr<JellyfinItem> Function() item,
  Size size = const Size(1280, 800),
  bool settle = true,
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
    ],
  );
  addTearDown(router.dispose);

  final container = ProviderContainer(
    overrides: [
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: JellyfinClient(server: _server),
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
Future<void> expectBackButtonPinned(WidgetTester tester, {double dy = -320}) async {
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
    final completer = Completer<JellyfinItem>();
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
}
