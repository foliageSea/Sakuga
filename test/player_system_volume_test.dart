import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/core/platform/system_volume.dart';
import 'package:sakuga/features/player/player_controls_controller.dart';

class _Player extends Fake implements Player {
  final volumeWrites = <double>[];

  @override
  PlayerState get state => const PlayerState(volume: 75);

  @override
  PlayerStream get stream => _Streams();

  @override
  Future<void> setVolume(double volume) async => volumeWrites.add(volume);
}

class _Streams extends Fake implements PlayerStream {
  @override
  dynamic noSuchMethod(Invocation invocation) => const Stream<Never>.empty();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const events = MethodChannel('com.foliage.sakuga/system_volume/changes');
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];

  Future<void> emit(double volume) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      events.name,
      codec.encodeSuccessEnvelope(volume),
      (_) {},
    );
  }

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemVolume.channel,
      (call) async {
        calls.add(call);
        // Simulate a device with 15 media volume steps.
        return ((call.arguments as double) * 15 / 100).round() * 100 / 15;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemVolume.channel,
      null,
    );
  });

  testWidgets(
    'Android controls use system volume and follow hardware changes',
    (tester) async {
      final player = _Player();
      final controller = MediaKitControlsController(player);
      var notifications = 0;
      controller.addListener(() => notifications++);
      await tester.pump();
      expect(calls.single.method, 'listen');

      await emit(40);
      expect(controller.volume, 40);
      expect(notifications, 1);

      await controller.setVolume(51);
      expect(controller.volume, closeTo(800 / 15, 0.001));
      expect(player.volumeWrites, isEmpty);
      expect(calls.last.arguments, 51.0);

      await controller.setVolume(0);
      expect(controller.volume, 0);
      await emit(20);
      expect(controller.volume, 20);

      controller.dispose();
      await tester.pump();
      expect(calls.last.method, 'cancel');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('desktop controls retain player volume', (tester) async {
    final player = _Player();
    final controller = MediaKitControlsController(player);
    expect(controller.volume, 75);
    await controller.setVolume(30);
    expect(player.volumeWrites, [30]);
    expect(calls, isEmpty);
    controller.dispose();
    await tester.pump();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'volume writes clamp and pending replies are safe after disposal',
    (tester) async {
      final reply = Completer<double>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemVolume.channel,
        (call) {
          expect(call.arguments, 100.0);
          return reply.future;
        },
      );
      final volume = SystemVolume();
      await tester.pump();
      final write = volume.setVolume(150);
      volume.dispose();
      reply.complete(100);
      await write;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
