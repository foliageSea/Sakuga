import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sakuga/app/mouse_back_navigation.dart';

Future<void> mouseClick(WidgetTester tester, int buttons) async {
  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await mouse.down(const Offset(20, 100));
  await mouse.up();
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

void main() {
  for (final blockBack in [false, true]) {
    testWidgets(
      'mouse back respects nested routing and PopScope ($blockBack)',
      (tester) async {
        var popNotifications = 0;
        final router = GoRouter(
          initialLocation: '/home/detail',
          routes: [
            ShellRoute(
              builder: (_, _, child) => child,
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, _) => const Scaffold(body: Text('Home')),
                  routes: [
                    GoRoute(
                      path: 'detail',
                      builder: (_, _) => PopScope<void>(
                        canPop: !blockBack,
                        onPopInvokedWithResult: (_, _) => popNotifications++,
                        child: const Scaffold(body: Text('Detail')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            builder: (_, child) => MouseBackNavigation(
              onBack: router.routerDelegate.popRoute,
              child: child!,
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final button in [
          kPrimaryMouseButton,
          kSecondaryMouseButton,
          kMiddleMouseButton,
          kForwardMouseButton,
        ]) {
          await mouseClick(tester, button);
          expect(find.text('Detail'), findsOneWidget);
          expect(popNotifications, 0);
        }

        // A dialog must close before the page beneath it can be popped.
        final context = tester.element(find.text('Detail'));
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Dialog')),
        );
        await tester.pumpAndSettle();
        await mouseClick(tester, kBackMouseButton);
        expect(find.text('Dialog'), findsNothing);
        expect(find.text('Detail'), findsOneWidget);
        expect(popNotifications, 0);

        await mouseClick(tester, kBackMouseButton);
        expect(popNotifications, 1);
        expect(find.text(blockBack ? 'Detail' : 'Home'), findsOneWidget);
        if (!blockBack) {
          await mouseClick(tester, kBackMouseButton);
          expect(find.text('Home'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
