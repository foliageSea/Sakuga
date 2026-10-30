import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_screenshot.dart';
import 'package:sakuga/features/player/player_subtitles.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

const _channel = MethodChannel('com.foliage.sakuga/image_clipboard');
const _galleryChannel = MethodChannel('com.foliage.sakuga/image_gallery');

Future<Uint8List> _videoFrame() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 100);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ByteData> _pixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  try {
    expect(image.width, 200);
    expect(image.height, 200);
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    codec.dispose();
  }
}

void main() {
  testWidgets('PNG includes styled captions, video and letterboxing', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: RepaintBoundary(
              key: key,
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: SubtitleCaption(
                  text: 'Subtitle',
                  fontSize: 16,
                  backgroundOpacity: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final subtitles = await boundary.toImage();
      try {
        final png = await composePlayerScreenshot(
          frame: await _videoFrame(),
          subtitles: subtitles,
          viewport: const Size(200, 200),
        );
        final data = await _pixels(png);
        int pixel(int x, int y) => data.getUint32((y * 200 + x) * 4);
        expect(pixel(0, 0), 0x000000FF);
        expect(pixel(100, 75), 0xFF0000FF);
        expect(pixel(0, 199), 0x000000FF);
        // The rendered Flutter caption contributes visible white text.
        var white = 0;
        for (var y = 160; y < 200; y++) {
          for (var x = 0; x < 200; x++) {
            if (pixel(x, y) == 0xFFFFFFFF) white++;
          }
        }
        expect(white, greaterThan(0));
      } finally {
        subtitles.dispose();
      }
    });
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    for (final fail in [false, true]) {
      testWidgets('screenshot flow on $platform, failure=$fail', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final gallery = platform == TargetPlatform.android;
        final channel = gallery ? _galleryChannel : _channel;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        Uint8List? written;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, gallery ? 'savePng' : 'writePng');
              if (fail) throw PlatformException(code: 'clipboard_failed');
              written = call.arguments as Uint8List;
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final frame = await tester.runAsync(_videoFrame);
        late Future<void> Function() copy;
        var captures = 0;
        final theme = createAppTheme(
          const AppSettings(),
          brightness: Brightness.dark,
          touch: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...FLocalizations.localizationsDelegates,
            ],
            builder: (context, child) => FTheme(
              data: theme,
              child: FToaster(child: child!),
            ),
            home: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: PlayerScreenshotSurface(
                  captureFrame: () async {
                    captures++;
                    return frame;
                  },
                  subtitles: const Align(
                    alignment: Alignment.bottomCenter,
                    child: SubtitleCaption(
                      text: 'Caption',
                      fontSize: 16,
                      backgroundOpacity: 0.5,
                    ),
                  ),
                  controlsBuilder: (context, action) {
                    copy = action;
                    return const ColoredBox(color: Color(0xFF00FF00));
                  },
                ),
              ),
            ),
          ),
        );
        // Pump the frame that the capture waits for, then await real image work.
        late Future<void> capturing;
        await tester.runAsync(() async {
          capturing = copy();
          final duplicate = copy();
          await tester.pump();
          await Future.wait([capturing, duplicate]);
        });
        await tester.pump();
        expect(captures, 1);
        if (fail) {
          expect(written, isNull);
          expect(
            find.text(
              gallery
                  ? 'Could not save the screenshot. Check storage permission and available space, then try again.'
                  : 'Could not copy the screenshot. Please try again.',
            ),
            findsOneWidget,
          );
        } else {
          expect(written, isNotNull);
          await tester.runAsync(() async {
            final data = await _pixels(written!);
            // Green controls cover the widget but are outside the subtitle capture.
            expect(data.getUint32((75 * 200 + 100) * 4), 0xFF0000FF);
          });
          expect(
            find.text(
              gallery
                  ? 'Screenshot saved to gallery.'
                  : 'Screenshot copied to clipboard.',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
