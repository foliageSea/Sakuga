import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum SuperResolutionMode { off, efficiency, quality }

const superResolutionShaderAssets = <SuperResolutionMode, List<String>>{
  SuperResolutionMode.off: [],
  SuperResolutionMode.efficiency: [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl',
    'Anime4K_Restore_CNN_S.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
  ],
  SuperResolutionMode.quality: [
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_VL.glsl',
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
  ],
};

/// Native mpv needs filesystem paths; Flutter asset URIs cannot be passed to
/// `glsl-shaders` or `sub-fonts-dir` directly.
class PlayerAssets {
  const PlayerAssets({
    required this.shadersDirectory,
    required this.fontsDirectory,
  });

  final Directory shadersDirectory;
  final Directory fontsDirectory;

  static Future<PlayerAssets>? _preparing;

  static Future<PlayerAssets> prepare() async {
    final existing = _preparing;
    if (existing != null) return existing;
    final future = _prepare();
    _preparing = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_preparing, future)) _preparing = null;
      rethrow;
    }
  }

  List<String> shaderPaths(SuperResolutionMode mode) => [
    for (final name in superResolutionShaderAssets[mode]!)
      '${shadersDirectory.path}${Platform.pathSeparator}$name',
  ];

  String shaderListValue(SuperResolutionMode mode) =>
      shaderPaths(mode).join(Platform.isWindows ? ';' : ':');

  static Future<PlayerAssets> _prepare() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      '${support.path}${Platform.pathSeparator}player-assets',
    );
    final shaders = Directory('${root.path}${Platform.pathSeparator}shaders');
    final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
    await Future.wait([
      shaders.create(recursive: true),
      fonts.create(recursive: true),
    ]);

    final shaderNames = superResolutionShaderAssets.values
        .expand((names) => names)
        .toSet();
    await Future.wait([
      for (final name in shaderNames)
        _copyAsset('assets/shaders/$name', shaders, name),
      _copyAsset('assets/MiSans-Regular.ttf', fonts, 'MiSans-Regular.ttf'),
    ]);
    return PlayerAssets(shadersDirectory: shaders, fontsDirectory: fonts);
  }

  static Future<void> _copyAsset(
    String asset,
    Directory directory,
    String name,
  ) async {
    final data = await rootBundle.load(asset);
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    if (await file.exists() && await file.length() == data.lengthInBytes) {
      return;
    }
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
}
