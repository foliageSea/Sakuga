import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:sakuga/core/logging/live_log_store.dart';
import 'package:sakuga/features/settings/live_log_controller.dart';
import 'package:sakuga/features/settings/live_logs_section.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

class ObservedLogStore extends LiveLogStore {
  bool get hasObservers => hasListeners;
}

void append(LiveLogStore store, String text, [Level level = Level.INFO]) =>
    store.add(level: level, time: DateTime(2026, 10, 13, 12), text: text);

Widget viewer(LiveLogStore store, {String language = 'en', double scale = 1}) {
  final theme = FTheme.neutral.light.touch;
  return ProviderScope(
    overrides: [liveLogStoreProvider.overrideWithValue(store)],
    child: MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...FLocalizations.localizationsDelegates,
      ],
      theme: theme.toApproximateMaterialTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: FTheme(
          data: theme,
          child: FToaster(child: child!),
        ),
      ),
      home: FScaffold(
        child: const SingleChildScrollView(child: LiveLogsSection()),
      ),
    ),
  );
}

void main() {
  test('session snapshot is ordered, immutable and count bounded', () {
    final store = LiveLogStore(maxEntries: 3);
    addTearDown(store.dispose);
    for (var i = 0; i < 5; i++) {
      append(store, 'entry $i');
    }
    expect(store.snapshot.map((entry) => entry.text), [
      'entry 2',
      'entry 3',
      'entry 4',
    ]);
    expect(store.latestId, 5);
    expect(() => store.snapshot.clear(), throwsUnsupportedError);
  });

  test(
    'text budget evicts oldest and truncation preserves surrogate pairs',
    () {
      final store = LiveLogStore(maxTextLength: 10, maxEntryLength: 6);
      addTearDown(store.dispose);
      append(store, '12345');
      append(store, '67890');
      expect(store.snapshot.length, 2);
      append(store, 'abcd😀tail');
      expect(store.snapshot.map((entry) => entry.text), ['67890', 'abcd…']);
      expect(store.snapshot.last.text.length, 5);
      append(store, 'abcdefghijk');
      expect(store.snapshot.map((entry) => entry.text), ['abcde…']);
    },
  );

  testWidgets(
    'high frequency notifications are coalesced and disposal cancels them',
    (tester) async {
      final store = LiveLogStore();
      var notifications = 0;
      store.addListener(() => notifications++);
      for (var i = 0; i < 2000; i++) {
        append(store, '$i');
      }
      expect(notifications, 0);
      expect(store.snapshot.length, 1000);
      await tester.pump(const Duration(milliseconds: 100));
      expect(notifications, 1);
      append(store, 'pending');
      store.dispose();
      await tester.pump(const Duration(milliseconds: 100));
      expect(notifications, 1);
    },
  );

  testWidgets(
    'pause freezes snapshot, resume catches up and clear is view-local',
    (tester) async {
      final store = LiveLogStore(maxEntries: 2);
      final first = LiveLogController(store);
      final second = LiveLogController(store);
      addTearDown(() {
        first.dispose();
        second.dispose();
        store.dispose();
      });
      append(store, 'initial');
      await tester.pump(const Duration(milliseconds: 100));
      first.togglePaused();
      append(store, 'new one');
      append(store, 'new two');
      await tester.pump(const Duration(milliseconds: 100));
      expect(first.copyText, 'initial');
      expect(second.copyText, 'new one\n\nnew two');
      first.togglePaused();
      expect(first.copyText, second.copyText);
      first.togglePaused();
      append(store, 'before clear, still pending');
      first.clearView();
      append(store, 'after clear');
      await tester.pump(const Duration(milliseconds: 100));
      expect(first.entries, isEmpty);
      first.togglePaused();
      expect(first.copyText, 'after clear');
      expect(second.entries.length, 2);
    },
  );

  test('search covers formatted details and combines with minimum level', () {
    final store = LiveLogStore();
    append(store, 'INFO [Worker] [worker.dart:12] Done');
    append(
      store,
      'SEVERE [Worker] Failed\nStateError\nstack.dart:42',
      Level.SEVERE,
    );
    final controller = LiveLogController(store);
    addTearDown(() {
      controller.dispose();
      store.dispose();
    });
    controller.setQuery('  WORKER  ');
    expect(controller.entries.length, 2);
    controller.setMinimumLevel(Level.WARNING);
    expect(controller.entries.single.level, Level.SEVERE);
    controller.setQuery('stack.dart:42');
    expect(controller.copyText, contains('StateError'));
    controller.setQuery('missing');
    expect(controller.entries, isEmpty);
  });

  testWidgets(
    'controller disposal detaches listener without buffered updates',
    (tester) async {
      final store = ObservedLogStore();
      final controller = LiveLogController(store);
      expect(store.hasObservers, isTrue);
      controller.dispose();
      expect(store.hasObservers, isFalse);
      append(store, 'still captured');
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.snapshot.single.text, 'still captured');
      store.dispose();
    },
  );

  testWidgets(
    'viewer receives records, filters levels, pauses, copies and clears',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1100);
      addTearDown(tester.view.reset);
      final store = LiveLogStore();
      addTearDown(store.dispose);
      append(store, 'INFO [Worker] started');
      append(store, 'SEVERE [Worker] failed\nError\nstack trace', Level.SEVERE);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(viewer(store));
      await tester.pumpAndSettle();
      expect(find.text('2 entries'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('log-level')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WARNING+').last);
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('copy-logs')));
      await tester.pumpAndSettle();
      expect(clipboard, 'SEVERE [Worker] failed\nError\nstack trace');
      await tester.tap(find.byKey(const ValueKey('copy-log-2')));
      await tester.pumpAndSettle();
      expect(clipboard, contains('stack trace'));
      await tester.enterText(find.byKey(const ValueKey('log-search')), 'STACK');
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pause-logs')));
      append(store, 'SEVERE stack new record', Level.SEVERE);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('1 entry'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pause-logs')));
      await tester.pumpAndSettle();
      expect(find.text('2 entries'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('clear-logs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('empty-logs-icon')), findsOneWidget);
      expect(find.text('No logs to display'), findsNothing);
      expect(store.snapshot.length, 3);
      append(store, 'SEVERE stack after clearing', Level.SEVERE);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('1 entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'manual scroll disables follow and latest appended row is followed',
    (tester) async {
      final store = LiveLogStore();
      addTearDown(store.dispose);
      for (var i = 0; i < 100; i++) {
        append(store, 'log $i${'\nstack frame' * (i % 7)}');
      }
      await tester.pumpWidget(viewer(store));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('live-log-list'));
      final scroll = tester.widget<ListView>(list).controller!;
      expect(scroll.position.extentAfter, closeTo(0, 0.5));
      expect(find.byKey(const ValueKey('live-log-100')), findsOneWidget);
      await tester.drag(list, const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, greaterThan(0));
      expect(
        tester
            .widget<FButton>(find.byKey(const ValueKey('follow-logs')))
            .selected,
        isFalse,
      );
      final readingOffset = scroll.offset;
      append(store, 'latest');
      await tester.pump(const Duration(milliseconds: 150));
      expect(scroll.offset, readingOffset);
      await tester.tap(find.byKey(const ValueKey('follow-logs')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, closeTo(0, 0.5));
      expect(find.text('latest', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('short logs start at the top and new records append below', (
    tester,
  ) async {
    final store = LiveLogStore();
    addTearDown(store.dispose);
    append(store, 'first');
    append(store, 'second');
    await tester.pumpWidget(viewer(store));
    await tester.pumpAndSettle();
    final list = find.byKey(const ValueKey('live-log-list'));
    final first = find.byKey(const ValueKey('live-log-1'));
    final second = find.byKey(const ValueKey('live-log-2'));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(list).dy);
    expect(
      tester.getTopLeft(second).dy,
      greaterThan(tester.getTopLeft(first).dy),
    );
    append(store, 'third');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    final third = find.byKey(const ValueKey('live-log-3'));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(list).dy);
    expect(
      tester.getTopLeft(third).dy,
      greaterThan(tester.getTopLeft(second).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final width in [390.0, 900.0]) {
    for (final language in ['en', 'zh']) {
      testWidgets(
        'log count is separate, subtle and aligned at $width in $language',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1000);
          addTearDown(tester.view.reset);
          final store = LiveLogStore();
          addTearDown(store.dispose);
          append(store, 'first');
          await tester.pumpWidget(viewer(store, language: language));
          await tester.pumpAndSettle();

          final count = find.byKey(const ValueKey('log-entry-count'));
          final text = tester.widget<Text>(count);
          final theme = FTheme.of(tester.element(count));
          expect(text.data, language == 'en' ? '1 entry' : '1 条');
          expect(
            text.textAlign,
            width < 480 ? TextAlign.left : TextAlign.right,
          );
          expect(text.style!.fontSize, theme.typography.body.xs.fontSize);
          expect(text.style!.color, theme.colors.mutedForeground);
          final list = find.byKey(const ValueKey('live-log-list'));
          for (final key in [
            'pause-logs',
            'follow-logs',
            'copy-logs',
            'clear-logs',
          ]) {
            expect(
              tester.getTopLeft(count).dy,
              greaterThan(tester.getBottomLeft(find.byKey(ValueKey(key))).dy),
            );
          }
          expect(
            tester.getTopLeft(list).dy,
            greaterThan(tester.getBottomLeft(count).dy),
          );
          if (width < 480) {
            expect(
              tester.getTopLeft(count).dx,
              closeTo(tester.getTopLeft(list).dx, 1),
            );
          } else {
            expect(
              tester.getTopRight(count).dx,
              closeTo(tester.getTopRight(list).dx, 1),
            );
          }
          append(store, 'second');
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(count).data,
            language == 'en' ? '2 entries' : '2 条',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  testWidgets('mobile rows copy on long press without per-row buttons', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.reset);
    final store = LiveLogStore();
    addTearDown(store.dispose);
    append(store, 'INFO [Worker] long press me');
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(viewer(store));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('copy-log-1')), findsNothing);
    await tester.longPress(find.byKey(const ValueKey('live-log-1')));
    await tester.pumpAndSettle();
    expect(clipboard, 'INFO [Worker] long press me');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  for (final language in ['en', 'zh']) {
    testWidgets('empty logs show a placeholder icon in $language', (
      tester,
    ) async {
      final store = LiveLogStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(viewer(store, language: language));
      await tester.pumpAndSettle();

      final empty = find.byKey(const ValueKey('empty-logs-icon'));
      final icon = tester.widget<Icon>(empty);
      final theme = FTheme.of(tester.element(empty));
      final label = language == 'en' ? 'No logs to display' : '暂无可显示的日志';
      expect(icon.icon, FLucideIcons.inbox);
      expect(icon.color, theme.colors.mutedForeground);
      expect(icon.semanticLabel, label);
      expect(find.text(label), findsNothing);

      append(store, 'new record');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(empty, findsNothing);
      expect(find.byKey(const ValueKey('live-log-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    testWidgets('mobile viewer supports $language and large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1000);
      addTearDown(tester.view.reset);
      final store = LiveLogStore();
      addTearDown(store.dispose);
      append(
        store,
        'WARNING [Worker] example.dart:12\n${'Long message ' * 30}',
        Level.WARNING,
      );
      await tester.pumpWidget(viewer(store, language: language, scale: 2));
      await tester.pumpAndSettle();
      expect(find.text(language == 'en' ? '1 entry' : '1 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
