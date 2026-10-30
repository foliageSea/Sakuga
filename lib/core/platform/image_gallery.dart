import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;

/// Saves PNG images to the Android system photo gallery.
abstract final class ImageGallery {
  static const _channel = MethodChannel('com.foliage.sakuga/image_gallery');

  /// Completes after the image is published to the gallery.
  static Future<void> savePng(Uint8List pngBytes) async {
    await _channel.invokeMethod<String>('savePng', pngBytes);
  }
}
