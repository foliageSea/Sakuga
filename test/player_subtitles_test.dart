import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_subtitles.dart';
import 'package:sakuga/features/player/player_slider.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  test('ASS, SSA and bitmap subtitle tracks use native rendering', () {
    for (final codec in [
      'ass',
      'ASS',
      'ssa',
      'dvd_subtitle',
      'DVDSUB',
      'hdmv_pgs_subtitle',
      'pgssub',
    ]) {
      final track = SubtitleTrack('1', null, null, codec: codec);
      expect(usesNativeSubtitleRendering(track, []), isTrue);
      expect(
        usesNativeSubtitleRendering(SubtitleTrack('1', null, null), [track]),
        isTrue,
      );
    }
    expect(
      usesNativeSubtitleRendering(
        SubtitleTrack('2', null, null, image: true),
        [],
      ),
      isTrue,
    );
  });

  test('text subtitles and disabled tracks keep native rendering off', () {
    for (final codec in ['subrip', 'webvtt', null]) {
      expect(
        usesNativeSubtitleRendering(
          SubtitleTrack('1', null, null, codec: codec),
          [],
        ),
        isFalse,
      );
    }
    final bitmap = SubtitleTrack('1', null, null, codec: 'dvd_subtitle');
    expect(usesNativeSubtitleRendering(SubtitleTrack.no(), [bitmap]), isFalse);
    expect(
      usesNativeSubtitleRendering(SubtitleTrack.auto(), [bitmap]),
      isFalse,
    );
  });

  test('subtitle preferences survive storage and other appearance updates', () {
    final original = const AppSettings()
        .copyWith(
          subtitleFontSize: 48,
          subtitleBackgroundOpacity: 0.25,
          subtitleVerticalPosition: 0.35,
        )
        .copyWith(themeColor: AppThemeColor.orange, fontScale: 1.2);
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.subtitleFontSize, 48);
    expect(restored.subtitleBackgroundOpacity, 0.25);
    expect(restored.subtitleVerticalPosition, 0.35);
    expect(restored.themeColor, AppThemeColor.orange);
    for (final json in <Map<String, dynamic>>[
      {},
      {
        'subtitleFontSize': -1,
        'subtitleBackgroundOpacity': 2,
        'subtitleVerticalPosition': -0.1,
      },
      {
        'subtitleFontSize': '32',
        'subtitleBackgroundOpacity': double.nan,
        'subtitleVerticalPosition': double.infinity,
      },
    ]) {
      final settings = AppSettings.fromJson(json);
      expect(settings.subtitleFontSize, 32);
      expect(settings.subtitleVerticalPosition, 0.9);
      expect(settings.subtitleBackgroundOpacity, closeTo(2 / 3, 0.0001));
    }
    final transparent = AppSettings.fromJson({
      'subtitleFontSize': 64,
      'subtitleBackgroundOpacity': 0,
    });
    expect(transparent.subtitleFontSize, 64);
    expect(transparent.subtitleBackgroundOpacity, 0);
  });

  testWidgets(
    'subtitle style saves changes for the next session without a preview',
    (tester) async {
      final repository = MemorySettings();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
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
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...FLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => FTheme(
              data: theme,
              child: FToaster(child: child!),
            ),
            home: Builder(
              builder: (context) => Center(
                child: FButton(
                  onPress: () => showSubtitleStyleDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(SubtitleCaption), findsNothing);
      final fontSlider = tester.widget<PlayerSlider>(
        find.byKey(const ValueKey('subtitle-font-size')),
      );
      fontSlider.onChange(2 / 3);
      fontSlider.onEnd!(2 / 3);
      await tester.pumpAndSettle();
      final opacitySlider = tester.widget<PlayerSlider>(
        find.byKey(const ValueKey('subtitle-background-opacity')),
      );
      opacitySlider.onChange(0.25);
      opacitySlider.onEnd!(0.25);
      await tester.pumpAndSettle();
      final positionSlider = tester.widget<PlayerSlider>(
        find.byKey(const ValueKey('subtitle-vertical-position')),
      );
      positionSlider.onChange(0.2);
      positionSlider.onEnd!(0.2);
      await tester.pumpAndSettle();
      expect(repository.value.subtitleFontSize, 48);
      expect(repository.value.subtitleBackgroundOpacity, 0.25);
      expect(repository.value.subtitleVerticalPosition, 0.2);

      expect(find.text('Close'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(FDialog), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlayerSlider>(
              find.byKey(const ValueKey('subtitle-vertical-position')),
            )
            .value,
        0.2,
      );
      expect(
        tester
            .widget<PlayerSlider>(
              find.byKey(const ValueKey('subtitle-font-size')),
            )
            .value,
        closeTo(2 / 3, 0.001),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final aspect in [16 / 9, 4 / 3, 9 / 16]) {
    testWidgets(
      'Android portrait subtitles follow video bounds for aspect $aspect',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final position in [
          0.0,
          0.5,
          const AppSettings().subtitleVerticalPosition,
          1.0,
        ]) {
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: const MediaQueryData(),
                child: SubtitlePlacement(
                  position: position,
                  videoAspectRatio: aspect,
                  child: const SizedBox(
                    key: ValueKey('caption'),
                    width: 200,
                    height: 30,
                  ),
                ),
              ),
            ),
          );
          final rect = tester.getRect(find.byKey(const ValueKey('caption')));
          final height = 390 / aspect;
          final top = (844 - height) / 2;
          expect(rect.top, greaterThanOrEqualTo(top));
          expect(rect.bottom, lessThanOrEqualTo(top + height));
          expect(rect.center.dx, 195);
          if (position == const AppSettings().subtitleVerticalPosition) {
            expect(rect.bottom, greaterThan(top + height * 0.75));
          }
        }
        // Rotation returns to the landscape placement rules.
        tester.view.physicalSize = const Size(844, 390);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('caption'))).bottom,
          378,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  for (final aspect in [null, 0.0, double.nan, double.infinity]) {
    testWidgets(
      'missing or invalid video aspect $aspect keeps safe portrait subtitles',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(),
              child: SubtitlePlacement(
                position: 1,
                videoAspectRatio: aspect,
                child: const SizedBox(
                  key: ValueKey('caption'),
                  width: 200,
                  height: 30,
                ),
              ),
            ),
          ),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('caption'))).bottom,
          832,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets('subtitle positions remain within the safe viewport', (
    tester,
  ) async {
    for (final position in [0.0, 0.5, 1.0]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: 30, bottom: 20),
            ),
            child: SizedBox.expand(
              child: SubtitlePlacement(
                position: position,
                child: const SizedBox(
                  key: ValueKey('caption'),
                  width: 120,
                  height: 50,
                ),
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byKey(const ValueKey('caption')));
      expect(rect.top, greaterThanOrEqualTo(30));
      expect(rect.bottom, lessThanOrEqualTo(580));
      expect(rect.center.dx, 400);
    }
  });
}
