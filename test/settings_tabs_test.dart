import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:material_ui/material_ui.dart';

import 'widget_test.dart' show appContainer, settle;

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final device in [
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
    ]) {
      testWidgets(
        'settings tabs swipe in both directions with $device on $platform',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 500);
          addTearDown(tester.view.resetPhysicalSize);
          final container = appContainer();
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const SakugaApp(),
            ),
          );
          container.read(routerProvider).go('/settings');
          await settle(tester);

          final pages = find.descendant(
            of: find.byKey(const ValueKey('settings-tabs')),
            matching: find.byType(PageView),
          );
          final controller = tester.widget<PageView>(pages).controller!;
          final width = tester.getSize(pages).width;
          Future<void> swipe(double direction) async {
            final offset = Offset(direction * width * 0.7, 0);
            if (device == PointerDeviceKind.trackpad) {
              await tester.trackpadFling(pages, offset, 1000);
            } else {
              await tester.drag(pages, offset, kind: device);
            }
            await settle(tester);
          }

          await swipe(1);
          expect(controller.page, closeTo(0, 0.001));
          await swipe(-1);
          expect(controller.page, closeTo(1, 0.001));
          expect(
            find.byKey(const ValueKey('theme-color-blue')).hitTestable(),
            findsOneWidget,
          );

          final vertical = find
              .descendant(
                of: pages,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      widget.axisDirection == AxisDirection.down,
                ),
              )
              .hitTestable();
          final position = tester
              .state<ScrollableState>(vertical.first)
              .position;
          expect(position.maxScrollExtent, greaterThan(0));
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(pages),
              scrollDelta: const Offset(0, 150),
            ),
          );
          await settle(tester);
          expect(position.pixels, greaterThan(0));
          expect(controller.page, closeTo(1, 0.001));

          await swipe(1);
          expect(controller.page, closeTo(0, 0.001));
          expect(
            find.byKey(const ValueKey('language-select')).hitTestable(),
            findsOneWidget,
          );

          await tester.ensureVisible(find.text('About this template'));
          await tester.tap(find.text('About this template'));
          await settle(tester);
          expect(controller.page, closeTo(4, 0.001));
          await swipe(-1);
          expect(controller.page, closeTo(4, 0.001));
          await swipe(1);
          expect(controller.page, closeTo(3, 0.001));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await settle(tester);
        },
        variant: TargetPlatformVariant({platform}),
      );
    }
  }

  testWidgets('overflowing settings tab labels support mouse dragging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = appContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    container.read(routerProvider).go('/settings');
    await settle(tester);

    final labels = find.descendant(
      of: find.byType(TabBar),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(labels).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      labels,
      Offset(-position.maxScrollExtent - 50, 0),
      kind: PointerDeviceKind.mouse,
    );
    await settle(tester);
    expect(position.pixels, greaterThan(0));
    expect(find.text('About this template').hitTestable(), findsOneWidget);
    await tester.tap(find.text('About this template'));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('font-notice')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
}
