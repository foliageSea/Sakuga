import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/shared/media_preview_card.dart';
import 'package:sakuga/shared/media_widgets.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets('hover zoom respects reduced motion: $reduceMotion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: FTheme(
            data: createAppTheme(
              const AppSettings(),
              brightness: Brightness.light,
              touch: false,
            ),
            child: Align(
              child: SizedBox(
                width: 220,
                child: MediaPreviewCard(
                  item: const MediaItem(
                    id: 'movie',
                    name: 'Movie',
                    type: MediaType.movie,
                    runtime: Duration(minutes: 90),
                  ),
                  zoomOnHover: true,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final image = find.byType(MediaImage);
      final frame = find.byType(AspectRatio);
      final title = find.text('Movie');
      final badge = find.text('01:30:00');
      final frameRect = tester.getRect(frame);
      final titleRect = tester.getRect(title);
      final badgeRect = tester.getRect(badge);
      expect(tester.getRect(image), frameRect);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(frameRect.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final midWidth = tester.getRect(image).width;
      await tester.pumpAndSettle();

      if (reduceMotion) {
        expect(midWidth, frameRect.width);
        expect(tester.getRect(image), frameRect);
      } else {
        final zoomed = tester.getRect(image);
        expect(zoomed.width, greaterThan(midWidth));
        expect(midWidth, greaterThan(frameRect.width));
        expect(zoomed.center, frameRect.center);
      }
      expect(tester.getRect(frame), frameRect);
      expect(tester.getRect(title), titleRect);
      expect(tester.getRect(badge), badgeRect);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.getRect(image), frameRect);
    });
  }

  testWidgets('preview card can be reached and activated with a keyboard', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: FTheme(
          data: createAppTheme(
            const AppSettings(),
            brightness: Brightness.light,
            touch: false,
          ),
          child: Align(
            child: SizedBox(
              width: 220,
              child: MediaPreviewCard(
                item: const MediaItem(
                  id: 'movie',
                  name: 'Movie',
                  type: MediaType.movie,
                ),
                onTap: () => activations++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
    expect(tester.takeException(), isNull);
  });
}
