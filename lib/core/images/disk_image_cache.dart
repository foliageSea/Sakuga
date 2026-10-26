import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// A file-backed cache for remote artwork.
///
/// Posters and backdrops are immutable for a given URL (the URL carries the
/// server-side image tag), so caching by URL is safe: a rescrape changes the
/// tag and therefore the URL.
class DiskImageCache {
  DiskImageCache._();

  static final DiskImageCache instance = DiskImageCache._();

  static const _maxAge = Duration(days: 30);

  Future<Directory>? _directory;
  bool _pruned = false;

  Future<File> fileFor(String url) async {
    final directory = await _directoryOf();
    return File('${directory.path}/${_fingerprint(url)}.img');
  }

  Future<Directory> _directoryOf() => _directory ??= _openDirectory();

  Future<Directory> _openDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/image-cache');
    await directory.create(recursive: true);
    if (!_pruned) {
      _pruned = true;
      unawaited(_prune(directory));
    }
    return directory;
  }

  Future<void> _prune(Directory directory) async {
    try {
      final cutoff = DateTime.now().subtract(_maxAge);
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (error) {
      debugPrint('Image cache prune failed: $error');
    }
  }

  /// Two independent 32-bit FNV-1a passes, so names stay short and stable.
  static String _fingerprint(String value) {
    var first = 0x811c9dc5;
    var second = 0x01000193;
    for (final byte in utf8.encode(value)) {
      first = ((first ^ byte) * 0x01000193) & 0xFFFFFFFF;
      second = ((second ^ byte) * 0x811c9dc5) & 0xFFFFFFFF;
    }
    return '${first.toRadixString(16).padLeft(8, '0')}'
        '${second.toRadixString(16).padLeft(8, '0')}';
  }
}

/// An [ImageProvider] that keeps decoded artwork on disk between launches.
class DiskCachedImage extends ImageProvider<DiskCachedImage> {
  const DiskCachedImage(this.url, {this.headers = const {}});

  final String url;
  final Map<String, String> headers;

  @override
  Future<DiskCachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DiskCachedImage>(this);

  @override
  ImageStreamCompleter loadImage(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: key.url,
    informationCollector: () => <DiagnosticsNode>[
      DiagnosticsProperty<ImageProvider>('Image provider', this),
    ],
  );

  Future<ui.Codec> _load(
    DiskCachedImage key,
    ImageDecoderCallback decode,
  ) async {
    final file = await DiskImageCache.instance.fileFor(key.url);
    Uint8List bytes;
    if (await file.exists() && await file.length() > 0) {
      bytes = await file.readAsBytes();
    } else {
      bytes = await _download(key.url, key.headers);
      await _store(file, bytes);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<void> _store(File file, Uint8List bytes) async {
    try {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } catch (error) {
      debugPrint('Image cache write failed: $error');
    }
  }

  Future<Uint8List> _download(String url, Map<String, String> headers) async {
    if (kDebugMode) debugPrint('IMG_DOWNLOAD $url');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Image request failed (${response.statusCode})',
          uri: Uri.parse(url),
        );
      }
      return await consolidateHttpClientResponseBytes(response)
          .timeout(const Duration(seconds: 30));
    } finally {
      client.close();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DiskCachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'DiskCachedImage("$url")';
}
