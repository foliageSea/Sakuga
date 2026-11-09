import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sakuga/features/player/player_assets.dart';
import 'package:sakuga/features/player/player_subtitle_rendering.dart';

/// Optional real-libmpv test; no server, network or licensed media required.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native ASS retains authored color and position in screenshots', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final directory = await Directory.systemTemp.createTemp('sakuga-ass-');
    final player = Player(configuration: subtitlePlayerConfiguration);
    final video = VideoController(player);
    final native = player.platform as NativePlayer;
    final rendering = SubtitleRenderingController(
      getProperty: (name) => native.getProperty(name),
      setProperty: (name, value) => native.setProperty(name, value),
    );
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    try {
      final media = File('${directory.path}/black.y4m');
      final bytes = BytesBuilder()
        ..add('YUV4MPEG2 W320 H180 F5:1 Ip A1:1 C420jpeg\n'.codeUnits);
      for (var frame = 0; frame < 40; frame++) {
        bytes.add('FRAME\n'.codeUnits);
        bytes.add(Uint8List(320 * 180)..fillRange(0, 320 * 180, 16));
        bytes.add(Uint8List(320 * 180 ~/ 2)..fillRange(0, 320 * 180 ~/ 2, 128));
      }
      await media.writeAsBytes(bytes.takeBytes());
      final ass = File('${directory.path}/effects.ass');
      await ass.writeAsString(r'''[Script Info]
ScriptType: v4.00+
PlayResX: 320
PlayResY: 180
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,MiSans,24,&H000000FF,&H0000FFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:08.00,Default,,0,0,0,,{\an7\pos(20,20)}ASS 中文 日本語
Dialogue: 0,0:00:00.00,0:00:08.00,Default,,0,0,0,,{\an7\move(20,85,160,85)\c&H00FF00&}MOVE
''');
      final srt = File('${directory.path}/plain.srt');
      await srt.writeAsString(
        '1\n00:00:00,000 --> 00:00:08,000\nPlain subtitle\n',
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 640,
              height: 360,
              child: Video(controller: video, controls: NoVideoControls),
            ),
          ),
        ),
      );
      debugPrint('ASS_NATIVE_STAGE video-mounted');
      final assets = await PlayerAssets.prepare().timeout(
        const Duration(seconds: 15),
      );
      debugPrint('ASS_NATIVE_STAGE assets-ready');
      await native
          .setProperty('sub-fonts-dir', assets.fontsDirectory.path)
          .timeout(const Duration(seconds: 15));
      debugPrint('ASS_NATIVE_STAGE fonts-ready');
      await native.setProperty('sub-font', 'MiSans');
      await native.setProperty('sub-ass-override', 'no');
      await native.setProperty('embeddedfonts', 'yes');
      await native.setProperty('secondary-sub-visibility', 'no');
      final ready = player.stream.position
          .firstWhere((value) => value >= const Duration(seconds: 1))
          .timeout(const Duration(seconds: 20));
      debugPrint('ASS_NATIVE_STAGE opening');
      await player.open(Media(media.path)).timeout(const Duration(seconds: 15));
      debugPrint('ASS_NATIVE_STAGE opened');
      await ready;
      await player.pause();
      await player.setSubtitleTrack(SubtitleTrack.uri(ass.uri.toString()));
      await rendering.synchronize(
        player.state.track.subtitle,
        player.state.tracks.subtitle,
      );
      expect(rendering.nativeRendering, isTrue);
      expect(rendering.flutterVisible, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      Future<({int red, int green, double greenX})> inspect(
        bool subtitles,
      ) async {
        final png = await player.screenshot(
          format: 'image/png',
          includeLibassSubtitles: subtitles,
        );
        expect(png, isNotNull);
        final codec = await ui.instantiateImageCodec(png!);
        final image = (await codec.getNextFrame()).image;
        try {
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          var red = 0;
          var green = 0;
          var greenX = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final offset = (y * image.width + x) * 4;
              final r = data.getUint8(offset);
              final g = data.getUint8(offset + 1);
              final b = data.getUint8(offset + 2);
              if (r > 100 && g < 70 && b < 70 && y < image.height ~/ 2) red++;
              if (g > 100 && r < 70 && b < 70) {
                green++;
                greenX += x;
              }
            }
          }
          return (
            red: red,
            green: green,
            greenX: green == 0 ? 0.0 : greenX / green,
          );
        } finally {
          image.dispose();
          codec.dispose();
        }
      }

      final authored = await inspect(true);
      expect(
        authored.red,
        greaterThan(30),
        reason: 'ASS red text must remain in the upper video region',
      );
      expect(authored.green, greaterThan(30));
      expect(
        (await inspect(false)).red,
        0,
        reason: 'video-only screenshot must exclude native captions',
      );
      await player.seek(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final moved = await inspect(true);
      expect(
        moved.greenX,
        greaterThan(authored.greenX + 30),
        reason: 'ASS move animation must advance',
      );
      await player.setSubtitleTrack(SubtitleTrack.uri(srt.uri.toString()));
      await rendering.synchronize(
        player.state.track.subtitle,
        player.state.tracks.subtitle,
      );
      expect(rendering.nativeRendering, isFalse);
      expect(rendering.flutterVisible, isTrue);
      await player.setSubtitleTrack(SubtitleTrack.no());
      await rendering.synchronize(
        SubtitleTrack.no(),
        player.state.tracks.subtitle,
      );
      expect(rendering.flutterVisible, isFalse);
      expect(errors, isEmpty);
    } finally {
      rendering.dispose();
      await subscription.cancel();
      await tester.pumpWidget(const SizedBox());
      await player.dispose();
      await directory.delete(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('ASS_NATIVE_TEST'));
}
