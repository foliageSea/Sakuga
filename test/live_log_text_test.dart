import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:sakuga/core/logging/live_log_store.dart';
import 'package:sakuga/features/settings/live_log_text.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.dark
        ? FTheme.neutral.dark.touch
        : FTheme.neutral.light.touch;

    Future<SelectableText> render(
      WidgetTester tester,
      Level level,
      String text,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FTheme(
            data: theme,
            child: LiveLogText(
              entry: LiveLogEntry(
                id: 1,
                level: level,
                time: DateTime(2026, 10, 13, 12),
                text: text,
              ),
            ),
          ),
        ),
      );
      return tester.widget<SelectableText>(find.byType(SelectableText));
    }

    testWidgets('level colors are distinct and readable in $brightness', (
      tester,
    ) async {
      final colors = <Color>{};
      for (final level in [
        Level.FINE,
        Level.CONFIG,
        Level.INFO,
        Level.WARNING,
        Level.SEVERE,
        Level.SHOUT,
      ]) {
        final text = '${level.name} [Worker] message';
        final widget = await render(tester, level, text);
        final color = widget.style!.color!;
        colors.add(color);
        expect(widget.textSpan!.toPlainText(), text);
        expect(widget.style!.fontFamily, 'monospace');
        final luminances = [
          color.computeLuminance(),
          theme.colors.background.computeLuminance(),
        ]..sort();
        expect(
          (luminances.last + 0.05) / (luminances.first + 0.05),
          greaterThanOrEqualTo(4.5),
          reason: '${level.name} in $brightness',
        );
      }
      expect(colors.length, 6);
    });

    testWidgets(
      'formatted headers are muted without changing $brightness text',
      (tester) async {
        const text =
            'SEVERE: 2026-10-13 12:00:00.123456: '
            '[Worker] [worker.dart:12] failed\nStateError\nstack.dart:42';
        final widget = await render(tester, Level.SEVERE, text);
        final spans = widget.textSpan!.children!.cast<TextSpan>();
        expect(widget.textSpan!.toPlainText(), text);
        expect(spans[0].text, 'SEVERE');
        expect(spans[0].style!.fontWeight, FontWeight.w600);
        expect(
          spans[1].text,
          ': 2026-10-13 12:00:00.123456: [Worker] [worker.dart:12] ',
        );
        expect(spans[1].style!.color, theme.colors.mutedForeground);
        expect(spans[2].text, 'failed\nStateError\nstack.dart:42');
      },
    );

    testWidgets('stack frames are hidden but messages stay in $brightness', (
      tester,
    ) async {
      const text =
          'SEVERE: 2026-10-13 12:00:00.123456: [Worker] [worker.dart:12] failed\n'
          'StateError: bad\n'
          '#0      main (package:app/main.dart:1:1)\n'
          '<asynchronous suspension>\n'
          '#1      run (package:app/run.dart:2:2)\n'
          '<asynchronous suspension>';
      final widget = await render(tester, Level.SEVERE, text);
      expect(
        widget.textSpan!.toPlainText(),
        'SEVERE: 2026-10-13 12:00:00.123456: [Worker] [worker.dart:12] failed\n'
        'StateError: bad',
      );
    });

    testWidgets('unformatted and custom levels preserve $brightness text', (
      tester,
    ) async {
      for (final text in [
        'plain message\nstack trace',
        '',
        'INFO',
        'INFORMATION is not a level prefix',
        'WARNING [Worker] mismatched prefix',
        'INFO [unterminated source',
      ]) {
        final widget = await render(tester, Level.INFO, text);
        expect(widget.textSpan!.toPlainText(), text);
      }
      final custom = await render(
        tester,
        const Level('CUSTOM', 950),
        'CUSTOM: custom message',
      );
      final warning = await render(tester, Level.WARNING, 'warning');
      expect(custom.style!.color, warning.style!.color);
      expect(custom.textSpan!.toPlainText(), 'CUSTOM: custom message');
      expect(tester.takeException(), isNull);
    });
  }
}
