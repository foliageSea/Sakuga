import 'dart:typed_data';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/media_server/server_config.dart';

enum ServerConfigExportResult { saved, shared, presented, cancelled }

final serverConfigFilesProvider = Provider<ServerConfigFiles>(
  (ref) => NativeServerConfigFiles(),
);

abstract interface class ServerConfigFiles {
  Future<Uint8List?> pick();

  Future<ServerConfigExportResult> export(
    Uint8List bytes, {
    Rect? sharePositionOrigin,
  });
}

class NativeServerConfigFiles implements ServerConfigFiles {
  static const _fileName = 'sakuga-servers.json';
  static const _json = XTypeGroup(
    label: 'JSON',
    extensions: ['json'],
    mimeTypes: ['application/json'],
    uniformTypeIdentifiers: ['public.json'],
  );

  @override
  Future<Uint8List?> pick() async {
    final file = await openFile(acceptedTypeGroups: [_json]);
    if (file == null) return null;
    if (await file.length() > serverConfigMaxBytes) {
      throw const FormatException();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > serverConfigMaxBytes) {
        throw const FormatException();
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  @override
  Future<ServerConfigExportResult> export(
    Uint8List bytes, {
    Rect? sharePositionOrigin,
  }) async {
    const mime = 'application/json';
    final file = XFile.fromData(bytes, mimeType: mime, name: _fileName);
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [file],
          fileNameOverrides: [_fileName],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => ServerConfigExportResult.shared,
        ShareResultStatus.unavailable => ServerConfigExportResult.presented,
        ShareResultStatus.dismissed => ServerConfigExportResult.cancelled,
      };
    }
    final location = await getSaveLocation(
      suggestedName: _fileName,
      acceptedTypeGroups: [_json],
    );
    if (location == null) return ServerConfigExportResult.cancelled;
    await file.saveTo(location.path);
    return ServerConfigExportResult.saved;
  }
}
