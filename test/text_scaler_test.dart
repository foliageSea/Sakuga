import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/app/text_scaler.dart';

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 20 ? 2 : 1.5);

  @override
  double get textScaleFactor => 2;
}

void main() {
  test('font tiers resolve per device pixel ratio band', () {
    final table = {
      1.0: [0.65, 0.8, 1.0],
      1.5: [0.65, 0.8, 1.0],
      1.51: [0.85, 1.0, 1.2],
      2.0: [0.85, 1.0, 1.2],
      2.49: [0.85, 1.0, 1.2],
      2.5: [0.57, 0.72, 0.92],
      3.0: [0.57, 0.72, 0.92],
      3.5: [0.57, 0.72, 0.92],
    };
    for (final MapEntry(key: ratio, value: expected) in table.entries) {
      expect(resolveFontScale(0.8, ratio), expected[0], reason: '$ratio small');
      expect(
        resolveFontScale(1.0, ratio),
        expected[1],
        reason: '$ratio standard',
      );
      expect(resolveFontScale(1.2, ratio), expected[2], reason: '$ratio large');
    }
  });

  test('tier boundaries snap stored values to the nearest tier', () {
    expect(resolveFontScale(0.89, 2), 0.85);
    expect(resolveFontScale(0.9, 2), 1.0);
    expect(resolveFontScale(1.1, 2), 1.0);
    expect(resolveFontScale(1.11, 2), 1.2);
  });

  test('app font scale composes with system scaling at every size', () {
    for (final systemScale in [1.0, 1.5, 2.0]) {
      for (final appScale in [0.8, 1.0, 1.2, 1.4, 1.6]) {
        final scaler = AppTextScaler(TextScaler.linear(systemScale), appScale);
        for (final size in [0.0, 12.0, 16.0, 32.0]) {
          expect(
            scaler.scale(size),
            closeTo(size * systemScale * appScale, 1e-9),
          );
        }
      }
    }
  });

  test('system nonlinear scaling is preserved, including at 100%', () {
    const system = _NonlinearTextScaler();
    for (final appScale in [0.8, 1.0, 1.6]) {
      final scaler = AppTextScaler(system, appScale);
      expect(scaler.scale(14), closeTo(28 * appScale, 1e-9));
      expect(scaler.scale(32), closeTo(48 * appScale, 1e-9));
    }
  });

  test('scaler equality tracks both system and app preferences', () {
    const scaler = AppTextScaler(TextScaler.linear(1.5), 1.2);
    const equal = AppTextScaler(TextScaler.linear(1.5), 1.2);
    expect(scaler, equal);
    expect(scaler.hashCode, equal.hashCode);
    expect(scaler, isNot(const AppTextScaler(TextScaler.linear(2), 1.2)));
    expect(scaler, isNot(const AppTextScaler(TextScaler.linear(1.5), 1.4)));
  });
}
