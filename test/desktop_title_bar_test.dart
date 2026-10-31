import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/shell.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

void main() {
  testWidgets('macOS window controls show glyphs together only while hovered', (
    tester,
  ) async {
    final window = FakeWindow(available: true, macOS: true);
    addTearDown(window.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(),
            brightness: Brightness.dark,
            touch: false,
          ),
          child: child!,
        ),
        home: Align(
          alignment: Alignment.topCenter,
          child: ListenableBuilder(
            listenable: window,
            builder: (context, _) => DesktopTitleBar(controller: window),
          ),
        ),
      ),
    );
    final controls = ['close', 'minimize', 'maximize'];
    for (final control in controls) {
      expect(find.byKey(ValueKey('mac-glyph-$control')), findsNothing);
    }
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 200));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('mac-close'))),
    );
    await tester.pump();
    for (final control in controls) {
      expect(find.byKey(ValueKey('mac-glyph-$control')), findsOneWidget);
    }
    for (final control in controls) {
      final button = find.byKey(ValueKey('mac-$control'));
      await mouse.moveTo(tester.getCenter(button));
      await tester.tap(button);
      await tester.pump();
    }
    expect(window.closes, 1);
    expect(window.minimizes, 1);
    expect(window.maximized, isTrue);
    expect(find.bySemanticsLabel('Restore'), findsOneWidget);
    await mouse.moveTo(const Offset(400, 200));
    await tester.pump();
    for (final control in controls) {
      expect(find.byKey(ValueKey('mac-glyph-$control')), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
