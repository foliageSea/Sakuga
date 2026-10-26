import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_subtitles.dart';
import 'package:sakuga/features/player/player_slider.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  test('subtitle preferences survive storage and other appearance updates', () {
    final original = const AppSettings()
        .copyWith(subtitleFontSize: 48, subtitleBackgroundOpacity: 0.25)
        .copyWith(themeColor: AppThemeColor.orange, fontScale: 1.2);
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.subtitleFontSize, 48);
    expect(restored.subtitleBackgroundOpacity, 0.25);
    expect(restored.themeColor, AppThemeColor.orange);
    for (final json in <Map<String, dynamic>>[
      {},
      {'subtitleFontSize': -1, 'subtitleBackgroundOpacity': 2},
      {'subtitleFontSize': '32', 'subtitleBackgroundOpacity': double.nan},
    ]) {
      final settings = AppSettings.fromJson(json);
      expect(settings.subtitleFontSize, 32);
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
    'subtitle style previews changes and saves for the next session',
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
      final caption = tester.widget<SubtitleCaption>(
        find.byType(SubtitleCaption),
      );
      expect(caption.fontSize, 48);
      expect(caption.backgroundOpacity, 0.25);
      expect(repository.value.subtitleFontSize, 48);
      expect(repository.value.subtitleBackgroundOpacity, 0.25);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
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
}
