import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_assets.dart';
import 'package:sakuga/features/player/player_page.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('super resolution button shows the active mode at phone width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var mode = SuperResolutionMode.off;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(),
            brightness: Brightness.dark,
            touch: true,
          ),
          child: child!,
        ),
        home: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topRight,
            child: PlayerSuperResolutionMenu(
              mode: mode,
              onChanged: (value) async => setState(() => mode = value),
            ),
          ),
        ),
      ),
    );
    final button = find.byKey(const ValueKey('super-resolution-menu'));
    expect(find.text('超分 · 效率'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-resolution-efficiency')));
    await tester.pumpAndSettle();
    expect(find.text('超分 · 效率'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-resolution-quality')));
    await tester.pumpAndSettle();
    expect(find.text('超分 · 质量'), findsOneWidget);
    expect(find.text('超分 · 效率'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('super-resolution-off')));
    await tester.pumpAndSettle();
    expect(find.text('超分 · 质量'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
