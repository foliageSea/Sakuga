import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/features/player/player_subtitle_selection_controller.dart';

void main() {
  const traditional = SubtitleTrack('1', '繁体', 'zh', codec: 'ass');
  const simplified = SubtitleTrack('2', '简体', 'zh', codec: 'subrip');
  const styled = SubtitleTrack('3', '简日双语', 'zh', codec: 'ass');
  const english = SubtitleTrack('4', 'English', 'eng', codec: 'subrip');

  test(
    'activation chooses Chinese and upgrades for late external ASS',
    () async {
      final writes = <SubtitleTrack>[];
      final controller = SubtitleSelectionController(
        setTrack: (track) async => writes.add(track),
      );
      addTearDown(controller.dispose);
      await controller.updateTracks([traditional]);
      expect(writes, isEmpty);
      await controller.activate([traditional]);
      await controller.updateTracks([traditional, simplified]);
      await controller.updateTracks([traditional, simplified, styled]);
      await controller.updateTracks([traditional, simplified, styled]);
      await controller.activate([traditional, simplified, styled]);
      expect(writes, [traditional, simplified, styled]);
      expect(controller.automatic, isTrue);
    },
  );

  for (final manual in [english, SubtitleTrack.no()]) {
    test(
      'manual ${manual.id} survives late tracks until auto selected',
      () async {
        final writes = <SubtitleTrack>[];
        final controller = SubtitleSelectionController(
          setTrack: (track) async => writes.add(track),
        );
        addTearDown(controller.dispose);
        await controller.activate([traditional, english]);
        await controller.select(manual);
        await controller.updateTracks([traditional, english, styled]);
        await controller.activate([traditional, english, styled]);
        expect(controller.automatic, isFalse);
        expect(writes, [traditional, manual]);
        await controller.select(SubtitleTrack.auto());
        expect(controller.automatic, isTrue);
        expect(writes.last, styled);
      },
    );
  }

  test(
    'no Chinese delegates to mpv and retries for newly added tracks',
    () async {
      final writes = <String>[];
      final controller = SubtitleSelectionController(
        setTrack: (track) async => writes.add(track.id),
      );
      addTearDown(controller.dispose);
      await controller.activate([]);
      await controller.updateTracks([english]);
      await controller.updateTracks([english]);
      await controller.updateTracks([english, traditional]);
      await controller.updateTracks([english]);
      expect(writes, ['auto', 'auto', '1', 'auto']);
    },
  );

  test('manual off wins over an in-flight automatic write', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final writes = <String>[];
    final controller = SubtitleSelectionController(
      setTrack: (track) async {
        if (track.id == '1') {
          started.complete();
          await release.future;
        }
        writes.add(track.id);
      },
    );
    addTearDown(controller.dispose);
    final automatic = controller.activate([traditional]);
    await started.future;
    final off = controller.select(SubtitleTrack.no());
    final tracks = controller.updateTracks([styled]);
    release.complete();
    await Future.wait([automatic, off, tracks]);
    expect(writes, ['1', 'no']);
    expect(controller.automatic, isFalse);
  });

  test('queued automatic writes are skipped after manual selection', () async {
    final writes = <String>[];
    final controller = SubtitleSelectionController(
      setTrack: (track) async => writes.add(track.id),
    );
    addTearDown(controller.dispose);
    await Future.wait([
      controller.activate([traditional]),
      controller.updateTracks([styled]),
      controller.select(english),
    ]);
    expect(writes, ['4']);
  });

  test('reset drains old writes and starts next media in auto mode', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final writes = <String>[];
    final controller = SubtitleSelectionController(
      setTrack: (track) async {
        if (track.id == '1') {
          started.complete();
          await release.future;
        }
        writes.add(track.id);
      },
    );
    addTearDown(controller.dispose);
    final automatic = controller.activate([traditional]);
    await started.future;
    final stale = controller.updateTracks([styled]);
    final reset = controller.reset();
    release.complete();
    await Future.wait([automatic, stale, reset]);
    expect(writes, ['1']);
    await controller.updateTracks([simplified]);
    expect(writes, ['1']);
    await controller.activate([simplified]);
    expect(writes, ['1', '2']);
    expect(controller.automatic, isTrue);
  });

  test('failed selection can retry without poisoning queue', () async {
    var fail = true;
    final writes = <String>[];
    final controller = SubtitleSelectionController(
      setTrack: (track) async {
        if (fail) throw StateError('unavailable');
        writes.add(track.id);
      },
    );
    addTearDown(controller.dispose);
    await expectLater(controller.activate([styled]), throwsStateError);
    fail = false;
    await controller.updateTracks([styled]);
    expect(writes, ['3']);
  });

  test('dispose skips queued selection', () async {
    final writes = <String>[];
    final controller = SubtitleSelectionController(
      setTrack: (track) async => writes.add(track.id),
    );
    final pending = controller.activate([styled]);
    controller.dispose();
    await pending;
    expect(writes, isEmpty);
  });
}
