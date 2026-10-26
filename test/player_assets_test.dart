import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/features/player/player_assets.dart';

void main() {
  test('super resolution modes contain ordered Anime4K pipelines', () {
    expect(superResolutionShaderAssets[SuperResolutionMode.off], isEmpty);
    expect(
      superResolutionShaderAssets[SuperResolutionMode.efficiency],
      containsAllInOrder([
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_M.glsl',
        'Anime4K_Upscale_CNN_x2_M.glsl',
        'Anime4K_AutoDownscalePre_x2.glsl',
      ]),
    );
    expect(
      superResolutionShaderAssets[SuperResolutionMode.quality],
      containsAllInOrder([
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_VL.glsl',
        'Anime4K_Upscale_CNN_x2_VL.glsl',
        'Anime4K_AutoDownscalePre_x2.glsl',
      ]),
    );
  });
}
