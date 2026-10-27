import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads device-wide GPU utilization percentage when supported by the host OS.
abstract final class GpuUsage {
  static const _channel = MethodChannel('com.foliage.sakuga/gpu_usage');

  /// Returns the current system-wide GPU utilization percentage in `0..100`,
  /// or `null` when the platform or hardware does not expose a counter.
  static Future<int?> readPercentage() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return null;
    }
    try {
      final value = await _channel.invokeMethod<num>('read');
      if (value == null || !value.isFinite) return null;
      return value.round().clamp(0, 100);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
