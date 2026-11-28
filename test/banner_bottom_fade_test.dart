import 'dart:ui' show ImageByteFormat;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/shared/media_widgets.dart';

void main() {
  testWidgets('banner fades to the page before a fractional bottom edge', (
    tester,
  ) async {
    const boundaryKey = ValueKey('banner-frame');
    await tester.pumpWidget(
      const Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 20,
            height: 100,
            child: ColoredBox(
              color: Color(0xFFFFFFFF),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 80.25,
                  width: 20,
                  child: BannerBottomFade(
                    fadeStart: 0.88,
                    child: ColoredBox(color: Color(0xFF000000)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(boundaryKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final pixels = (await image.toByteData(
          format: ImageByteFormat.rawRgba,
        ))!;
        int redAt(int y) => pixels.getUint8((y * image.width + 20) * 4);
        expect(redAt(120), 0);
        expect(redAt(152), inExclusiveRange(0, 255));
        // The final interior pixel, fractional boundary and following row
        // all match the page instead of leaving a dark horizontal edge.
        expect([
          for (final y in [159, 160, 161]) redAt(y),
        ], everyElement(255));
      } finally {
        image.dispose();
      }
    });
  });
}
