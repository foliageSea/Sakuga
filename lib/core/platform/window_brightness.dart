import 'package:flutter/services.dart';

/// Overrides only the current Android window, without changing system settings.
abstract final class WindowBrightness {
  static const channel = MethodChannel('com.foliage.sakuga/window_brightness');

  static Future<double> read() async =>
      (await channel.invokeMethod<double>('read'))!.clamp(0, 1);

  static Future<void> set(double value) =>
      channel.invokeMethod<void>('set', value.clamp(0, 1));

  static Future<void> reset() => channel.invokeMethod<void>('reset');
}
