import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/platform/window_brightness.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_controls_controller.dart';
import 'package:sakuga/features/player/player_gestures.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

class _Controller extends PlayerControlsController {
  @override
  bool playing = true;
  @override
  bool get buffering => false;
  @override
  double? get downloadBytesPerSecond => null;
  @override
  Duration position = const Duration(seconds: 30);
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  Duration get buffer => Duration.zero;
  @override
  double volume = 50;
  @override
  double rate = 1;
  int seeks = 0;
  Future<void>? boostGate;
  @override
  Future<void> playOrPause() async => playing = !playing;
  @override
  Future<void> seek(Duration value) async {
    position = value;
    seeks++;
  }

  @override
  Future<void> setVolume(double value) async => volume = value;
  @override
  Future<void> setRate(double value) async {
    if (value == 2) await boostGate;
    rate = value;
  }
}

void main() {
  Future<void> pumpSurface(
    WidgetTester tester,
    _Controller controller, {
    VoidCallback? onTap,
    Future<void> Function()? onFullscreen,
    ValueChanged<bool>? onInteraction,
    bool enabled = true,
  }) async {
    final theme = createAppTheme(
      const AppSettings(),
      brightness: Brightness.dark,
      touch: true,
    );
    await tester.pumpWidget(
      MaterialApp(
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
        home: PlayerGestureSurface(
          controller: controller,
          enabled: enabled,
          onTap: onTap ?? () {},
          onToggleFullscreen: onFullscreen ?? () async {},
          onInteractionChanged: onInteraction ?? (_) {},
        ),
      ),
    );
  }

  testWidgets(
    'Android hold boosts to 2x and release restores the original rate',
    (tester) async {
      final controller = _Controller()..rate = 1.25;
      final interactions = <bool>[];
      var taps = 0;
      await pumpSurface(
        tester,
        controller,
        onTap: () => taps++,
        onInteraction: interactions.add,
      );
      final hold = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.rate, 2);
      expect(find.text('2×'), findsOneWidget);
      await hold.up();
      await tester.pump();
      expect(controller.rate, 1.25);
      expect(find.text('2×'), findsNothing);
      expect(interactions.last, isFalse);
      expect(taps, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('release restores speed after a delayed boost write', (
    tester,
  ) async {
    final gate = Completer<void>();
    final controller = _Controller()..boostGate = gate.future;
    await pumpSurface(tester, controller);
    final hold = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await hold.up();
    gate.complete();
    await tester.pump();
    expect(controller.rate, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('desktop hold does not change playback speed', (tester) async {
    final controller = _Controller();
    await pumpSurface(tester, controller);
    final hold = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(controller.rate, 1);
    await hold.up();
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final interruption in [
    'cancel',
    'dispose',
    'background',
    'disable',
    'replace',
  ]) {
    testWidgets('Android hold restores rate on $interruption', (tester) async {
      final controller = _Controller()..rate = 1.5;
      await pumpSurface(tester, controller);
      final hold = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.rate, 2);
      switch (interruption) {
        case 'cancel':
          await hold.cancel();
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case 'disable':
          await pumpSurface(tester, controller, enabled: false);
        case 'replace':
          await pumpSurface(tester, _Controller());
      }
      await tester.pump();
      expect(controller.rate, 1.5);
      if (interruption != 'cancel') await hold.up();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('hold does not accelerate paused playback on $platform', (
      tester,
    ) async {
      final controller = _Controller()..playing = false;
      await pumpSurface(tester, controller);
      final hold = await tester.startGesture(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.rate, 1);
      expect(controller.playing, isFalse);
      await hold.up();
      await tester.pump(const Duration(seconds: 1));
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('Android taps toggle controls and double taps toggle playback', (
    tester,
  ) async {
    final controller = _Controller();
    var taps = 0;
    var fullscreen = 0;
    await pumpSurface(
      tester,
      controller,
      onTap: () => taps++,
      onFullscreen: () async => fullscreen++,
    );
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 1);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(controller.playing, isFalse);
    expect(taps, 1);
    expect(fullscreen, 0);
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('horizontal swipes preview, commit within bounds and cancel', (
    tester,
  ) async {
    final controller = _Controller();
    final interactions = <bool>[];
    await pumpSurface(tester, controller, onInteraction: interactions.add);
    var drag = await tester.startGesture(const Offset(300, 300));
    await drag.moveBy(const Offset(30, 0));
    await drag.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('player-gesture-hud')), findsOneWidget);
    expect(controller.position, const Duration(seconds: 30));
    expect(controller.seeks, 0);
    await drag.up();
    await tester.pump();
    expect(controller.position, greaterThan(const Duration(seconds: 30)));
    expect(controller.playing, isTrue);
    expect(interactions.last, isFalse);

    final position = controller.position;
    drag = await tester.startGesture(const Offset(500, 300));
    await drag.moveBy(const Offset(-30, 0));
    await drag.moveBy(const Offset(-200, 0));
    await tester.pump();
    await drag.cancel();
    await tester.pump();
    expect(controller.position, position);
    expect(controller.seeks, 1);
    expect(find.byKey(const ValueKey('player-gesture-hud')), findsNothing);

    await tester.dragFrom(const Offset(100, 300), const Offset(650, 0));
    await tester.pump();
    expect(controller.position, controller.duration);
    await tester.dragFrom(const Offset(750, 300), const Offset(-650, 0));
    await tester.pump();
    expect(controller.position, Duration.zero);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'vertical swipes adjust the selected side and restore brightness',
    (tester) async {
      final controller = _Controller();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowBrightness.channel, (call) async {
            calls.add(call);
            return call.method == 'read' ? 0.4 : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowBrightness.channel, null),
      );
      await pumpSurface(tester, controller);
      await tester.dragFrom(const Offset(600, 400), const Offset(0, -150));
      await tester.pump();
      expect(controller.volume, greaterThan(50));
      expect(calls, isEmpty);
      final volume = controller.volume;
      final drag = await tester.startGesture(const Offset(200, 400));
      await drag.moveBy(const Offset(0, -30));
      await tester.pump();
      await drag.moveBy(const Offset(0, -100));
      await tester.pump();
      await drag.up();
      await tester.pump();
      final value =
          calls.lastWhere((call) => call.method == 'set').arguments as double;
      expect(value, greaterThan(0.4));
      expect(value, lessThanOrEqualTo(1));
      expect(controller.volume, volume);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.last.method, 'reset');
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('delayed brightness read does not write a guessed brightness', (
    tester,
  ) async {
    final controller = _Controller();
    final read = Completer<double>();
    final values = <double>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowBrightness.channel, (call) async {
          if (call.method == 'read') return read.future;
          if (call.method == 'set') values.add(call.arguments as double);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowBrightness.channel, null),
    );
    await pumpSurface(tester, controller);
    final drag = await tester.startGesture(const Offset(200, 400));
    await drag.moveBy(const Offset(0, -30));
    await tester.pump();
    await drag.moveBy(const Offset(0, -45));
    await tester.pump();
    expect(values, isEmpty);
    read.complete(0.2);
    await tester.pump();
    expect(values.single, closeTo(0.3, 0.01));
    await drag.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('cancelled brightness gesture ignores a late native response', (
    tester,
  ) async {
    final controller = _Controller();
    final read = Completer<double>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowBrightness.channel, (call) async {
          calls.add(call.method);
          return call.method == 'read' ? read.future : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowBrightness.channel, null),
    );
    await pumpSurface(tester, controller);
    final drag = await tester.startGesture(const Offset(200, 400));
    await drag.moveBy(const Offset(0, -30));
    await tester.pump();
    await drag.moveBy(const Offset(0, -45));
    await drag.cancel();
    await tester.pump();
    read.complete(0.2);
    await tester.pump();
    expect(calls, ['read']);
    expect(find.byKey(const ValueKey('player-gesture-hud')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, ['read']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'desktop keeps fullscreen double click and ignores touch swipes',
    (tester) async {
      final controller = _Controller();
      var fullscreen = 0;
      await pumpSurface(
        tester,
        controller,
        onFullscreen: () async => fullscreen++,
      );
      await tester.dragFrom(const Offset(300, 300), const Offset(200, 0));
      await tester.pump();
      expect(controller.seeks, 0);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(fullscreen, 1);
      expect(controller.playing, isTrue);
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
