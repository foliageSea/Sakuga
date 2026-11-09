import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_quality.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

Widget _app({
  required PlaybackQuality? selected,
  required Future<void> Function(PlaybackQuality?) onChanged,
  bool enabled = true,
  String language = 'en',
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...FLocalizations.localizationsDelegates,
  ],
  builder: (context, child) => FTheme(
    data: createAppTheme(
      const AppSettings(),
      brightness: Brightness.dark,
      touch: false,
    ),
    child: child!,
  ),
  home: Align(
    alignment: Alignment.topRight,
    child: PlayerQualityMenu(
      selected: selected,
      enabled: enabled,
      onChanged: onChanged,
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('quality-menu')));
  await tester.pumpAndSettle();
}

void main() {
  test('labels presets as resolution and bitrate, highest first', () {
    expect(playbackQualityPresets.map((quality) => quality.label), [
      '1080p (20 Mbps)',
      '720p (8 Mbps)',
      '480p (3 Mbps)',
      '360p (1 Mbps)',
    ]);
    expect(formatBitrate(1500000), '1.5 Mbps');
    expect(formatBitrate(720000), '720 kbps');
    for (var i = 1; i < playbackQualityPresets.length; i++) {
      expect(
        playbackQualityPresets[i].height,
        lessThan(playbackQualityPresets[i - 1].height),
      );
      expect(
        playbackQualityPresets[i].bitrate,
        lessThan(playbackQualityPresets[i - 1].bitrate),
      );
    }
    expect(const PlaybackQuality(720, 8000000), playbackQualityPresets[1]);
  });

  for (final language in ['en', 'zh']) {
    testWidgets('selects a cap and returns to maximum in $language', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      PlaybackQuality? selected;
      final requests = <PlaybackQuality?>[];
      StateSetter? update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _app(
              language: language,
              selected: selected,
              onChanged: (quality) async {
                requests.add(quality);
                update!(() => selected = quality);
              },
            );
          },
        ),
      );
      await _open(tester);
      expect(find.text(language == 'zh' ? '最高画质' : 'Maximum'), findsOneWidget);
      expect(find.text('1080p (20 Mbps)'), findsOneWidget);
      expect(find.text('360p (1 Mbps)'), findsOneWidget);
      // Only the options: no play method or explanatory text.
      expect(find.byType(FItem), findsNWidgets(5));
      expect(
        tester
            .widget<FItem>(find.byKey(const ValueKey('quality-max')))
            .selected,
        isTrue,
      );

      // Re-selecting the active option does not renegotiate.
      await tester.tap(find.byKey(const ValueKey('quality-max')));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);

      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('quality-720')));
      await tester.pumpAndSettle();
      expect(requests, [const PlaybackQuality(720, 8000000)]);

      await _open(tester);
      expect(
        tester
            .widget<FItem>(find.byKey(const ValueKey('quality-720')))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('quality-max')));
      await tester.pumpAndSettle();
      expect(requests.last, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabled while loading or switching', (tester) async {
    await tester.pumpWidget(
      _app(
        selected: null,
        enabled: false,
        onChanged: (_) async => fail('Disabled menu must not renegotiate'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('quality-menu')))
          .onPress,
      isNull,
    );
    await _open(tester);
    expect(find.byType(FItem), findsNothing);
  });
}
