import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/detail/played_status_button.dart';
import 'package:sakuga/features/home/home_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/widgets.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Server',
  baseUrl: 'http://localhost:8096',
  apiKey: 'key',
);

class _Client extends FakeMediaServerClient {
  _Client() : super(server: _server);
  final calls = <(String, String, bool)>[];
  Completer<void>? pending;
  Object? error;

  @override
  Future<void> setPlayed(
    String userId,
    String itemId, {
    required bool played,
  }) async {
    calls.add((userId, itemId, played));
    if (error != null) throw error!;
    await pending?.future;
  }
}

class _Progress extends Fake implements PlaybackProgressRepository {
  int? pending = 123;
  final cleared = <(String, String, String, int)>[];
  int? concurrentSave;

  @override
  Future<int?> load({
    required String serverId,
    required String userId,
    required String itemId,
  }) async => pending;

  @override
  Future<void> clearIfMatches({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  }) async {
    cleared.add((serverId, userId, itemId, positionTicks));
    if (concurrentSave != null) pending = concurrentSave;
    if (pending == positionTicks) pending = null;
  }
}

MediaItem _item({bool played = false}) => MediaItem(
  id: 'movie',
  name: 'Movie',
  type: MediaType.movie,
  played: played,
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  _Client client, {
  bool played = false,
  String language = 'en',
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(language: 'en'),
            brightness: Brightness.light,
            touch: false,
          ),
          child: child!,
        ),
        home: Center(
          child: SizedBox(
            width: 400,
            child: PlayedStatusButton(
              client: client,
              userId: 'user',
              item: _item(played: played),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _container(_Client client, _Progress progress) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      activeServerProvider.overrideWithValue(_server),
      playbackProgressRepositoryProvider.overrideWithValue(progress),
      libraryViewsProvider.overrideWith(
        (ref) async =>
            LibraryData(client: client, userId: 'user', views: const []),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _markPlayed(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('played-status-movie')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('played-status-confirm')));
  await tester.pump();
}

void main() {
  for (final dismiss in [false, true]) {
    testWidgets(
      'mark played waits for confirmation and cancellation preserves progress ($dismiss)',
      (tester) async {
        final client = _Client();
        final progress = _Progress();
        final container = _container(client, progress);
        await _pump(tester, container, client);
        final callback = tester.widget<FButton>(find.byType(FButton)).onPress!;
        callback();
        callback();
        await tester.pumpAndSettle();
        expect(find.byType(FDialog), findsOneWidget);
        expect(find.text('Mark “Movie” as played?'), findsOneWidget);
        expect(client.calls, isEmpty);
        expect(progress.pending, 123);
        expect(progress.cleared, isEmpty);
        if (dismiss) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byKey(const ValueKey('played-status-cancel')));
        }
        await tester.pumpAndSettle();
        expect(find.byType(FDialog), findsNothing);
        expect(client.calls, isEmpty);
        expect(progress.pending, 123);
        expect(progress.cleared, isEmpty);
        await _markPlayed(tester);
        await tester.pumpAndSettle();
        expect(client.calls, [('user', 'movie', true)]);
      },
    );
  }

  testWidgets(
    'success clears matching pending progress, refreshes data and toggles',
    (tester) async {
      final client = _Client();
      final progress = _Progress();
      var itemLoads = 0;
      var episodeLoads = 0;
      var resumeLoads = 0;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          activeServerProvider.overrideWithValue(_server),
          playbackProgressRepositoryProvider.overrideWithValue(progress),
          libraryViewsProvider.overrideWith(
            (ref) async =>
                LibraryData(client: client, userId: 'user', views: const []),
          ),
          libraryItemProvider.overrideWith((ref, query) async {
            itemLoads++;
            return _item();
          }),
          seriesEpisodesProvider.overrideWith((ref, query) async {
            episodeLoads++;
            return [];
          }),
          resumeItemsProvider.overrideWith((ref) async {
            resumeLoads++;
            return [];
          }),
        ],
      );
      addTearDown(container.dispose);
      final itemProvider = libraryItemProvider((
        userId: 'user',
        itemId: 'movie',
      ));
      final episodesProvider = seriesEpisodesProvider((
        userId: 'user',
        seriesId: 'series',
        seasonId: 'season',
      ));
      final subscriptions = [
        container.listen(itemProvider, (_, _) {}),
        container.listen(episodesProvider, (_, _) {}),
        container.listen(resumeItemsProvider, (_, _) {}),
        container.listen(libraryViewsProvider, (_, _) {}),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });
      await container.read(libraryViewsProvider.future);
      await _pump(tester, container, client);
      expect(find.bySemanticsLabel('Movie: Mark as played'), findsOneWidget);
      await _markPlayed(tester);
      await tester.pumpAndSettle();
      expect(client.calls, [('user', 'movie', true)]);
      expect(progress.pending, isNull);
      expect(progress.cleared, [('server', 'user', 'movie', 123)]);
      expect(itemLoads, 2);
      expect(episodeLoads, 2);
      expect(resumeLoads, 2);
      expect(find.text('Mark as unplayed'), findsOneWidget);
      await tester.tap(find.text('Mark as unplayed'));
      await tester.pumpAndSettle();
      expect(client.calls.last, ('user', 'movie', false));
      expect(find.text('Mark as played'), findsOneWidget);
    },
  );

  testWidgets('pending request shows loading and ignores duplicate callbacks', (
    tester,
  ) async {
    final client = _Client()..pending = Completer<void>();
    final progress = _Progress();
    final container = _container(client, progress);
    await _pump(tester, container, client, played: true);
    final callback = tester.widget<FButton>(find.byType(FButton)).onPress!;
    callback();
    callback();
    await tester.pump();
    expect(client.calls, [('user', 'movie', false)]);
    expect(tester.widget<FButton>(find.byType(FButton)).onPress, isNull);
    expect(find.byType(FCircularProgress), findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);
    client.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mark as played'), findsOneWidget);
  });

  testWidgets('failure stays visible, preserves progress and allows retry', (
    tester,
  ) async {
    final client = _Client()..error = const AppException(FailureKind.server);
    final progress = _Progress();
    final container = _container(client, progress);
    await _pump(tester, container, client);
    await _markPlayed(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(progress.pending, 123);
    expect(progress.cleared, isEmpty);
    expect(find.text('Mark as played'), findsOneWidget);
    client.error = null;
    await _markPlayed(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNotice), findsNothing);
    expect(find.text('Mark as unplayed'), findsOneWidget);
  });

  testWidgets(
    'completion after unmount still clears captured checkpoint safely',
    (tester) async {
      final client = _Client()..pending = Completer<void>();
      final progress = _Progress()..concurrentSave = 456;
      final container = _container(client, progress);
      await _pump(tester, container, client);
      await _markPlayed(tester);
      await tester.pumpWidget(const SizedBox());
      client.pending!.complete();
      await tester.pumpAndSettle();
      expect(progress.cleared, [('server', 'user', 'movie', 123)]);
      expect(progress.pending, 456);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'server switch does not refresh the new server with an old result',
    (tester) async {
      final client = _Client()..pending = Completer<void>();
      final progress = _Progress();
      var resumeLoads = 0;
      final overrides = [
        activeServerProvider.overrideWithValue(_server),
        playbackProgressRepositoryProvider.overrideWithValue(progress),
        libraryViewsProvider.overrideWith(
          (ref) async =>
              LibraryData(client: client, userId: 'user', views: const []),
        ),
        resumeItemsProvider.overrideWith((ref) async {
          resumeLoads++;
          return [];
        }),
      ];
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: overrides,
      );
      addTearDown(container.dispose);
      final librarySubscription = container.listen(
        libraryViewsProvider,
        (_, _) {},
      );
      final resumeSubscription = container.listen(
        resumeItemsProvider,
        (_, _) {},
      );
      addTearDown(librarySubscription.close);
      addTearDown(resumeSubscription.close);
      await container.read(libraryViewsProvider.future);
      await _pump(tester, container, client);
      await _markPlayed(tester);
      container.updateOverrides([
        activeServerProvider.overrideWithValue(
          const ServerProfile(
            id: 'other',
            name: 'Other',
            baseUrl: 'http://other:8096',
            apiKey: 'other-key',
          ),
        ),
        ...overrides.skip(1),
      ]);
      await tester.pumpWidget(const SizedBox());
      client.pending!.complete();
      await tester.pumpAndSettle();
      expect(progress.cleared, [('server', 'user', 'movie', 123)]);
      expect(resumeLoads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preserves a newer checkpoint saved while the request is in flight',
    (tester) async {
      final client = _Client()..pending = Completer<void>();
      final progress = _Progress();
      final container = _container(client, progress);
      await _pump(tester, container, client);
      await _markPlayed(tester);
      await tester.pump();
      progress.pending = 456;
      client.pending!.complete();
      await tester.pumpAndSettle();
      expect(progress.cleared, [('server', 'user', 'movie', 123)]);
      expect(progress.pending, 456);
    },
  );

  testWidgets(
    'completion after container disposal does not access dead providers',
    (tester) async {
      final client = _Client()..pending = Completer<void>();
      final progress = _Progress();
      final container = _container(client, progress);
      await _pump(tester, container, client);
      await _markPlayed(tester);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      client.pending!.complete();
      await tester.pumpAndSettle();
      expect(progress.pending, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Chinese played action is localized', (tester) async {
    final client = _Client();
    final progress = _Progress();
    final container = _container(client, progress);
    await _pump(tester, container, client, played: true, language: 'zh');
    expect(find.text('标为未播放'), findsOneWidget);
    expect(find.bySemanticsLabel('Movie: 标为未播放'), findsOneWidget);
  });
}
