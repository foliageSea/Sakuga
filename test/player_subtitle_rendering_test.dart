import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/features/player/player_subtitle_rendering.dart';

void main() {
  test('libass and Android fallback font are enabled at creation', () {
    expect(subtitlePlayerConfiguration.libass, isTrue);
    expect(
      subtitlePlayerConfiguration.libassAndroidFont,
      'assets/MiSans-Regular.ttf',
    );
    expect(subtitlePlayerConfiguration.libassAndroidFontName, 'MiSans');
  });

  for (final codec in ['ass', 'ssa', 'hdmv_pgs_subtitle', 'subrip', 'webvtt']) {
    test('auto selects $codec with only one renderer active', () async {
      final writes = <String>[];
      final controller = SubtitleRenderingController(
        getProperty: (name) async => '2',
        setProperty: (name, value) async => writes.add('$name=$value'),
      );
      addTearDown(controller.dispose);
      await controller.synchronize(SubtitleTrack.auto(), [
        SubtitleTrack('2', null, null, codec: codec),
      ]);
      final native = codec != 'subrip' && codec != 'webvtt';
      expect(controller.nativeRendering, native);
      expect(controller.flutterVisible, !native);
      expect(writes, ['sub-visibility=${native ? 'yes' : 'no'}']);
      await controller.synchronize(SubtitleTrack.no(), []);
      expect(controller.flutterVisible, isFalse);
      expect(controller.nativeRendering, isFalse);
      expect(writes.last, 'sub-visibility=no');
    });
  }

  test('external URI sentinel resolves the actual native ASS codec', () async {
    final controller = SubtitleRenderingController(
      getProperty: (name) async =>
          {
            'sid': '7',
            'track-list/count': '1',
            'track-list/0/type': 'sub',
            'track-list/0/id': '7',
            'track-list/0/codec': 'ass',
          }[name] ??
          '',
      setProperty: (name, value) async {},
    );
    addTearDown(controller.dispose);
    await controller.synchronize(
      SubtitleTrack.uri('https://media.test/subtitle'),
      [],
    );
    expect(controller.nativeRendering, isTrue);
    expect(controller.flutterVisible, isFalse);
  });

  test(
    'unknown codec stays native rather than flattening authored styles',
    () async {
      final controller = SubtitleRenderingController(
        getProperty: (name) async => name == 'sid' ? '7' : '0',
        setProperty: (name, value) async {},
      );
      addTearDown(controller.dispose);
      await controller.synchronize(SubtitleTrack.auto(), []);
      expect(controller.nativeRendering, isTrue);
      expect(controller.flutterVisible, isFalse);
    },
  );

  test(
    'rapid switch invalidates stale native queries and hides text immediately',
    () async {
      final pending = Completer<String>();
      var delayed = false;
      final writes = <String>[];
      final controller = SubtitleRenderingController(
        getProperty: (name) => delayed ? pending.future : Future.value('1'),
        setProperty: (name, value) async => writes.add(value),
      );
      addTearDown(controller.dispose);
      await controller.synchronize(SubtitleTrack.auto(), [
        SubtitleTrack('1', null, null, codec: 'subrip'),
      ]);
      expect(controller.flutterVisible, isTrue);
      delayed = true;
      final stale = controller.synchronize(SubtitleTrack.auto(), []);
      expect(controller.flutterVisible, isFalse);
      await Future<void>.value();
      final latest = controller.synchronize(SubtitleTrack.no(), []);
      pending.complete('2');
      await Future.wait([stale, latest]);
      expect(controller.flutterVisible, isFalse);
      expect(writes, ['no', 'no']);
    },
  );

  test('reset on episode change invalidates pending old media work', () async {
    final pending = Completer<String>();
    final writes = <String>[];
    final controller = SubtitleRenderingController(
      getProperty: (name) => pending.future,
      setProperty: (name, value) async => writes.add(value),
    );
    addTearDown(controller.dispose);
    final stale = controller.synchronize(SubtitleTrack.auto(), []);
    await Future<void>.value();
    controller.reset();
    pending.complete('1');
    await stale;
    expect(writes, isEmpty);
    expect(controller.flutterVisible, isFalse);
  });

  test(
    'native property failure does not poison later subtitle changes',
    () async {
      var fail = true;
      final controller = SubtitleRenderingController(
        getProperty: (name) async {
          if (fail) throw StateError('not loaded');
          return '1';
        },
        setProperty: (name, value) async {},
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.synchronize(SubtitleTrack.auto(), []),
        throwsStateError,
      );
      fail = false;
      await controller.synchronize(SubtitleTrack.auto(), [
        SubtitleTrack('1', null, null, codec: 'subrip'),
      ]);
      expect(controller.flutterVisible, isTrue);
    },
  );

  test(
    'dispose invalidates native queries without notifying listeners',
    () async {
      final pending = Completer<String>();
      final controller = SubtitleRenderingController(
        getProperty: (name) => pending.future,
        setProperty: (name, value) async =>
            fail('disposed controller must not write'),
      );
      final operation = controller.synchronize(SubtitleTrack.auto(), []);
      await Future<void>.value();
      controller.dispose();
      pending.complete('1');
      await operation;
    },
  );
}
