import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/shared/media_preview_card.dart';

void main() {
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
