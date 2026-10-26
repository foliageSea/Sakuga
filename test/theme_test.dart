import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';

void main() {
  test(
    'theme tokens propagate to component shapes, colors and focus rings',
    () {
      for (final brightness in Brightness.values) {
        for (final touch in [true, false]) {
          for (final color in AppThemeColor.values) {
            for (final scale in [0.0, 1.0, 2.0]) {
              final theme = createAppTheme(
                AppSettings(themeColor: color, radiusScale: scale),
                brightness: brightness,
                touch: touch,
              );
              final button = theme.buttonStyles.primary.md.decoration.resolve(
                {},
              ) as ShapeDecoration;
              final card = theme.cardStyle.decoration as ShapeDecoration;
              expect(button.color, color.primary(brightness));
              expect(
                (button.shape as RoundedSuperellipseBorder).borderRadius,
                BorderRadius.circular(10 * scale),
              );
              expect(
                (card.shape as RoundedSuperellipseBorder).borderRadius,
                BorderRadius.circular(14 * scale),
              );
              expect(
                theme.style.focusedOutlineStyle.color,
                theme.colors.primary,
              );
              expect(
                theme.style.focusedOutlineStyle.borderRadius,
                BorderRadius.circular(10 * scale),
              );
              final luminances = [
                theme.colors.primary.computeLuminance(),
                theme.colors.primaryForeground.computeLuminance(),
              ]..sort();
              expect(
                (luminances[1] + 0.05) / (luminances[0] + 0.05),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
        }
      }
    },
  );
}
