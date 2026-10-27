import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;

/// Writes PNG images to the native system clipboard.
abstract final class ImageClipboard {
  static const _channel = MethodChannel('com.foliage.sakuga/image_clipboard');

  /// Completes after the native clipboard accepts [pngBytes].
  ///
  /// Native clipboard failures and unsupported platforms propagate to callers.
  static Future<void> writePng(Uint8List pngBytes) async {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (pngBytes.length < signature.length) {
      throw ArgumentError('Image clipboard requires PNG bytes.');
    }
    for (var index = 0; index < signature.length; index++) {
      if (pngBytes[index] != signature[index]) {
        throw ArgumentError('Image clipboard requires PNG bytes.');
      }
    }
    await _channel.invokeMethod<void>('writePng', pngBytes);
  }
}
