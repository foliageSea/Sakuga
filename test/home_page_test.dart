import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_models.dart';
import 'package:sakuga/data/jellyfin/server_profile.dart';
import 'package:sakuga/data/jellyfin/server_repository.dart';
import 'package:sakuga/features/home/home_page.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

JellyfinItem _resumableEpisode() => const JellyfinItem(
  id: 'episode-1',
  name: 'Pilot',
  type: 'Episode',
  imageTags: {},
  seriesId: 'series-1',
  seriesName: 'Resumed Series',
  seasonId: 'season-1',
  indexNumber: 1,
  parentIndexNumber: 1,
  userData: {'PlayedPercentage': 42.0},
);

JellyfinItem _series() => const JellyfinItem(
  id: 'series-2',
  name: 'Recent Series',
  type: 'Series',
  imageTags: {},
);

/// Pumps the home page behind a router whose destination routes are stubs, so
/// the test only checks where a card tap navigates.
Future<void> pumpHome(
  WidgetTester tester, {
  List<JellyfinItem>? resume,
  List<JellyfinItem>? latest,
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
          client: JellyfinClient(server: _server),
          userId: 'user-1',
          views: const [],
        ),
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

void main() {
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
}
