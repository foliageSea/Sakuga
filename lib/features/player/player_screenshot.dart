import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../core/platform/image_clipboard.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';

/// Keeps the subtitle capture layer separate from buttons and other overlays.
class PlayerScreenshotSurface extends StatefulWidget {
  const PlayerScreenshotSurface({
    required this.captureFrame,
    required this.subtitles,
    required this.controlsBuilder,
    super.key,
  });

  final Future<Uint8List?> Function() captureFrame;
  final Widget subtitles;
  final Widget Function(BuildContext context, Future<void> Function() copy)
  controlsBuilder;

  @override
  State<PlayerScreenshotSurface> createState() =>
      _PlayerScreenshotSurfaceState();
}

class _PlayerScreenshotSurfaceState extends State<PlayerScreenshotSurface> {
  final _subtitleKey = GlobalKey();
  bool _capturing = false;

  Future<void> _copyScreenshot() async {
    if (_capturing) return;
    _capturing = true;
    ui.Image? subtitles;
    try {
      // The video is a native texture; capture it through the player instead of
      // assuming Flutter can read it back from a repaint boundary.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _subtitleKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final viewport = boundary.size;
      subtitles = await boundary.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      final frame = await widget.captureFrame().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted) return;
      if (frame == null || frame.isEmpty) {
        throw StateError('No video frame available');
      }
      final png = await composePlayerScreenshot(
        frame: frame,
        subtitles: subtitles,
        viewport: viewport,
      );
      if (!mounted) return;
      await ImageClipboard.writePng(png);
      if (mounted) notifyUser(context, context.l10n.screenshotCopied);
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.screenshotFailed);
    } finally {
      subtitles?.dispose();
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(key: _subtitleKey, child: widget.subtitles),
      widget.controlsBuilder(context, _copyScreenshot),
    ],
  );
}

/// Combines the native video frame with the exact Flutter subtitle appearance.
/// The viewport preserves letterboxing and captions drawn in the black bars.
Future<Uint8List> composePlayerScreenshot({
  required Uint8List frame,
  required ui.Image subtitles,
  required Size viewport,
}) async {
  final codec = await ui.instantiateImageCodec(frame);
  ui.Image? video;
  ui.Image? result;
  ui.Picture? picture;
  try {
    video = (await codec.getNextFrame()).image;
    final outputSize = Size(
      subtitles.width.toDouble(),
      subtitles.height.toDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF000000), BlendMode.src);
    final videoSize = Size(video.width.toDouble(), video.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, videoSize, viewport);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & viewport,
    );
    canvas.save();
    canvas.scale(
      outputSize.width / viewport.width,
      outputSize.height / viewport.height,
    );
    canvas.drawImageRect(video, Offset.zero & videoSize, destination, Paint());
    canvas.restore();
    canvas.drawImage(subtitles, Offset.zero, Paint());
    picture = recorder.endRecording();
    result = await picture.toImage(subtitles.width, subtitles.height);
    final bytes = await result.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Could not encode screenshot');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    result?.dispose();
    picture?.dispose();
    video?.dispose();
    codec.dispose();
  }
}
