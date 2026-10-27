import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_models.dart';
import 'package:sakuga/data/jellyfin/server_profile.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/features/player/player_controls.dart';
import 'package:sakuga/features/player/player_controls_controller.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

JellyfinItem episode(String id, int season, int number) => JellyfinItem(
  id: id,
  name: id,
  type: 'Episode',
  imageTags: const {},
  parentIndexNumber: season,
  indexNumber: number,
  seriesId: 'series',
);

void main() {
  test('next episode follows server order across gaps and seasons', () {
    final episodes = [
      episode('first', 1, 1),
      episode('third', 1, 3),
      episode('next-season', 2, 1),
    ];

    expect(nextPlayerEpisode(episodes, 'first')?.id, 'third');
    expect(nextPlayerEpisode(episodes, 'third')?.id, 'next-season');
    expect(nextPlayerEpisode(episodes, 'next-season'), isNull);
    expect(nextPlayerEpisode(episodes, 'missing'), isNull);
    expect(nextPlayerEpisode(episodes, null), isNull);
    expect(nextPlayerEpisode([], 'first'), isNull);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('Forui controls play, seek, mute and resize at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _ControlsController();
      final currentId = ValueNotifier<String?>('first');
      final switching = ValueNotifier(false);
      addTearDown(controller.dispose);
      addTearDown(currentId.dispose);
      addTearDown(switching.dispose);
      var fullscreen = false;
      final container = ProviderContainer(
        overrides: [
          libraryViewsProvider.overrideWith(
            (ref) async => LibraryData(
              client: JellyfinClient(
                server: const ServerProfile(
                  id: 'server',
                  name: 'Server',
                  baseUrl: 'https://media.example',
                  apiKey: '',
                ),
              ),
              userId: 'user',
              views: const [],
            ),
          ),
          libraryItemProvider.overrideWith(
            (ref, query) async => episode(query.itemId, 1, 1),
          ),
          seriesEpisodesProvider.overrideWith(
            (ref, query) async => [
              episode('first', 1, 1),
              episode('second', 1, 2),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      final theme = createAppTheme(
        const AppSettings(themeColor: AppThemeColor.orange),
        brightness: Brightness.dark,
        touch: false,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...FLocalizations.localizationsDelegates,
            ],
            builder: (context, child) => FTheme(
              data: theme,
              child: FToaster(child: child!),
            ),
            home: PlayerControls(
              controller: controller,
              onToggleFullscreen: () async => fullscreen = !fullscreen,
              onExitFullscreen: () async => fullscreen = false,
              fullscreen: false,
              header: const Text('Episode'),
              itemId: currentId,
              switching: switching,
              onSelectEpisode: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('player-next-episode')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-episodes-menu')),
        findsOneWidget,
      );
      expect(find.byType(FSlider), findsWidgets);
      expect(tester.takeException(), isNull);

      // Exercise actual pointer dragging, including FSlider's onEnd callback.
      final seek = find.byKey(const ValueKey('player-seek'));
      final bounds = tester.getRect(seek);
      final drag = await tester.startGesture(
        Offset(bounds.left + bounds.width * 0.25, bounds.center.dy),
      );
      await tester.pump();
      await drag.moveBy(const Offset(24, 0));
      await tester.pump();
      await drag.moveTo(
        Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
      );
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.position.inSeconds, closeTo(90, 5));
      await tester.tap(find.byKey(const ValueKey('player-mute')));
      await tester.pumpAndSettle();
      expect(controller.volume, 0);
      await tester.tap(find.byKey(const ValueKey('player-mute')));
      await tester.pumpAndSettle();
      expect(controller.volume, 80);
      await tester.tap(find.byKey(const ValueKey('player-fullscreen')));
      await tester.pumpAndSettle();
      expect(fullscreen, isTrue);

      await tester.tap(find.byKey(const ValueKey('player-play-pause')));
      await tester.pumpAndSettle();
      expect(controller.playing, isTrue);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        0,
      );
      // Buffering remains visible even after the control bar auto-hides.
      controller.updateBuffering(true);
      await tester.pump();
      expect(find.byType(FCircularProgress), findsOneWidget);
      expect(find.byKey(const ValueKey('player-download-speed')), findsNothing);
      controller.updateBuffering(true, speed: 1536);
      await tester.pump();
      expect(find.text('1.5 KB/s'), findsOneWidget);
      controller.updateBuffering(true, speed: 2.5 * 1024 * 1024);
      await tester.pump();
      expect(find.text('2.5 MB/s'), findsOneWidget);
      controller.updateBuffering(true, speed: 0);
      await tester.pump();
      expect(find.text('0 B/s'), findsOneWidget);
      controller.updateBuffering(true);
      await tester.pump();
      expect(find.byType(FCircularProgress), findsOneWidget);
      expect(find.byKey(const ValueKey('player-download-speed')), findsNothing);
      controller.updateBuffering(false, speed: 1536);
      await tester.pump();
      expect(find.byType(FCircularProgress), findsNothing);
      expect(find.byKey(const ValueKey('player-download-speed')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.playing, isFalse);
      expect(
        tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
            .opacity,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'retained buttons appear after metadata loads and follow episode changes',
    (tester) async {
      final library = Completer<LibraryData>();
      final item = Completer<JellyfinItem>();
      final episodes = Completer<List<JellyfinItem>>();
      final currentId = ValueNotifier<String?>('first');
      final switching = ValueNotifier(false);
      final selected = <String>[];
      final values = [episode('first', 1, 1), episode('second', 1, 2)];
      final container = ProviderContainer(
        overrides: [
          libraryViewsProvider.overrideWith((ref) => library.future),
          libraryItemProvider.overrideWith((ref, query) => item.future),
          seriesEpisodesProvider.overrideWith((ref, query) => episodes.future),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(currentId.dispose);
      addTearDown(switching.dispose);
      // These instances stay in the bar, as they do when media_kit retains the
      // theme's original button widgets after an asynchronous metadata load.
      final bar = Row(
        children: [
          PlayerEpisodeButton(
            itemId: currentId,
            switching: switching,
            onSelectEpisode: (value) async => selected.add(value.id),
          ),
          PlayerEpisodeButton(
            itemId: currentId,
            switching: switching,
            menu: true,
            onSelectEpisode: (value) async => selected.add(value.id),
          ),
        ],
      );
      final theme = createAppTheme(
        const AppSettings(),
        brightness: Brightness.dark,
        touch: false,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...FLocalizations.localizationsDelegates,
            ],
            builder: (context, child) => FTheme(data: theme, child: child!),
            home: Scaffold(
              body: Align(alignment: Alignment.bottomCenter, child: bar),
            ),
          ),
        ),
      );
      const nextKey = ValueKey('player-next-episode');
      const menuKey = ValueKey('player-episodes-menu');
      expect(find.byKey(nextKey), findsNothing);
      library.complete(
        LibraryData(
          client: JellyfinClient(
            server: const ServerProfile(
              id: 'server',
              name: 'Server',
              baseUrl: 'https://media.example',
              apiKey: '',
            ),
          ),
          userId: 'user',
          views: const [],
        ),
      );
      await tester.pumpAndSettle();
      item.complete(values.first);
      await tester.pumpAndSettle();
      expect(find.byKey(menuKey), findsOneWidget);
      expect(find.byKey(nextKey), findsOneWidget);
      expect(
        tester.widget<PlayerControlButton>(find.byKey(nextKey)).onPress,
        isNull,
      );

      episodes.complete(values);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(nextKey));
      expect(selected, ['second']);
      await tester.tap(find.byKey(menuKey));
      await tester.pumpAndSettle();
      expect(find.text('S01E01 · first'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('player-episode-second')));
      await tester.pumpAndSettle();
      expect(selected, ['second', 'second']);

      switching.value = true;
      await tester.pumpAndSettle();
      expect(
        tester.widget<PlayerControlButton>(find.byKey(nextKey)).onPress,
        isNull,
      );
      expect(
        tester.widget<PlayerControlButton>(find.byKey(menuKey)).onPress,
        isNull,
      );
      switching.value = false;
      currentId.value = 'second';
      await tester.pumpAndSettle();
      expect(find.byKey(menuKey), findsOneWidget);
      expect(
        tester.widget<PlayerControlButton>(find.byKey(nextKey)).onPress,
        isNull,
      );
      expect(
        tester.widget<PlayerControlButton>(find.byKey(menuKey)).onPress,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _ControlsController extends PlayerControlsController {
  @override
  bool playing = false;
  @override
  bool buffering = false;
  @override
  double? downloadBytesPerSecond;

  void updateBuffering(bool value, {double? speed}) {
    buffering = value;
    downloadBytesPerSecond = speed;
    notifyListeners();
  }

  @override
  Duration position = const Duration(seconds: 30);
  @override
  Duration duration = const Duration(minutes: 2);
  @override
  Duration buffer = const Duration(seconds: 90);
  @override
  double volume = 80;

  @override
  Future<void> playOrPause() async {
    playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
    notifyListeners();
  }
}
