import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_buffer.dart';
import 'package:sakuga/l10n/generated/app_localizations_en.dart';
import 'package:sakuga/l10n/generated/app_localizations_zh.dart';

import 'fakes.dart';
import 'widget_test.dart' show appContainer, settle;

void main() {
  test('buffer preference defaults, persists and rejects unknown values', () {
    expect(const AppSettings().playbackBufferMiB, 32);
    final restored = AppSettings.fromJson(
      const AppSettings().copyWith(playbackBufferMiB: 256).toJson(),
    );
    expect(restored.playbackBufferMiB, 256);
    // Other preferences survive buffer updates.
    expect(
      const AppSettings(seekForwardSeconds: 10)
          .copyWith(playbackBufferMiB: 128)
          .seekForwardSeconds,
      10,
    );
    for (final invalid in <Object?>[null, 64, -1, '128', 128.5, 4096]) {
      expect(
        AppSettings.fromJson({'playbackBufferMiB': invalid}).playbackBufferMiB,
        32,
        reason: '$invalid',
      );
    }
  });

  test('applies the forward limit and keeps the back buffer bounded', () async {
    for (final mib in playbackBufferPresetsMiB) {
      final writes = <String, String>{};
      await applyPlaybackBuffer(
        (name, value) async => writes[name] = value,
        mib,
      );
      expect(writes, {
        'demuxer-max-bytes': '${mib * 1024 * 1024}',
        'demuxer-max-back-bytes': '${32 * 1024 * 1024}',
      });
    }
  });

  test('labels presets in both languages', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();
    expect(
      playbackBufferPresetsMiB.map((mib) => playbackBufferLabel(en, mib)),
      ['Standard · 32 MiB', 'Large · 128 MiB', 'Extra large · 256 MiB'],
    );
    expect(
      playbackBufferPresetsMiB.map((mib) => playbackBufferLabel(zh, mib)),
      ['标准 · 32 MiB', '较大 · 128 MiB', '大 · 256 MiB'],
    );
  });

  testWidgets('general settings change and save the playback buffer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = MemorySettings();
    final container = appContainer(settingsRepository: repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    container.read(routerProvider).go('/settings');
    await settle(tester);
    await tester.tap(find.text('General'));
    await settle(tester);

    final select = find.byKey(const ValueKey('playback-buffer-select'));
    expect(select, findsOneWidget);
    expect(find.text('Standard · 32 MiB'), findsOneWidget);

    await tester.tap(select);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('playback-buffer-128')).last);
    await settle(tester);

    expect(container.read(settingsProvider).playbackBufferMiB, 128);
    expect(repository.value.playbackBufferMiB, 128);
    expect(find.text('Large · 128 MiB'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
