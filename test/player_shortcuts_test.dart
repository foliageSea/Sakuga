import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_shortcuts.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/widgets.dart';

import 'fakes.dart';
import 'widget_test.dart' show appContainer, settle;

const _backwardKey = ValueKey('seek-backward-seconds');
const _forwardKey = ValueKey('seek-forward-seconds');
Finder _stepper(Key key, {required bool increase}) => find.ancestor(
  of: find.descendant(
    of: find.byKey(key),
    matching: find.byIcon(increase ? FLucideIcons.plus : FLucideIcons.minus),
  ),
  matching: find.byType(FButton),
);

Finder _value(Key key, int seconds) =>
    find.descendant(of: find.byKey(key), matching: find.text('$seconds s'));

Future<void> _step(
  WidgetTester tester,
  Key key, {
  required bool increase,
}) async {
  final button = _stepper(key, increase: increase);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _openDialog(
  WidgetTester tester,
  MemorySettings repository, {
  double textScale = 1,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repository),
      initialSettingsProvider.overrideWithValue(repository.value),
    ],
  );
  addTearDown(container.dispose);
  final theme = createAppTheme(
    repository.value,
    brightness: Brightness.dark,
    touch: false,
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: FTheme(
            data: theme,
            child: FToaster(child: child!),
          ),
        ),
        home: Builder(
          builder: (context) => Center(
            child: FButton(
              onPress: () => showPlayerShortcutDialog(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('seek intervals round trip independently and survive other updates', () {
    final original = const AppSettings()
        .copyWith(seekBackwardSeconds: 1)
        .copyWith(seekForwardSeconds: 600)
        .copyWith(language: 'zh', subtitleFontSize: 48);
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.seekBackwardSeconds, 1);
    expect(restored.seekForwardSeconds, 600);
    expect(restored.language, 'zh');
    expect(restored.subtitleFontSize, 48);
    expect(const AppSettings().seekBackwardSeconds, 5);
    expect(const AppSettings().seekForwardSeconds, 5);
    expect(AppSettings.fromJson({}).seekBackwardSeconds, 5);
    expect(AppSettings.fromJson({}).seekForwardSeconds, 5);
  });

  test('invalid stored intervals fall back independently to five seconds', () {
    for (final value in <Object?>[
      null,
      0,
      -1,
      601,
      1.0,
      5.5,
      600.0,
      '15',
      true,
      [],
      {},
      double.nan,
      double.infinity,
    ]) {
      final backwardInvalid = AppSettings.fromJson({
        'seekBackwardSeconds': value,
        'seekForwardSeconds': 42,
      });
      expect(backwardInvalid.seekBackwardSeconds, 5, reason: '$value');
      expect(backwardInvalid.seekForwardSeconds, 42);
      final forwardInvalid = AppSettings.fromJson({
        'seekBackwardSeconds': 17,
        'seekForwardSeconds': value,
      });
      expect(forwardInvalid.seekBackwardSeconds, 17);
      expect(forwardInvalid.seekForwardSeconds, 5, reason: '$value');
    }
  });

  test('constructor and copyWith assert both seek interval boundaries', () {
    for (final value in [0, 601]) {
      expect(
        () => AppSettings(seekBackwardSeconds: value),
        throwsAssertionError,
      );
      expect(
        () => AppSettings(seekForwardSeconds: value),
        throwsAssertionError,
      );
      expect(
        () => const AppSettings().copyWith(seekBackwardSeconds: value),
        throwsAssertionError,
      );
      expect(
        () => const AppSettings().copyWith(seekForwardSeconds: value),
        throwsAssertionError,
      );
    }
  });

  testWidgets('steppers save immediately and retain values after dismissal', (
    tester,
  ) async {
    final repository = MemorySettings()
      ..value = const AppSettings(
        seekBackwardSeconds: 8,
        seekForwardSeconds: 21,
      );
    final container = await _openDialog(tester, repository);
    expect(_value(_backwardKey, 8), findsOneWidget);
    expect(_value(_forwardKey, 21), findsOneWidget);
    final l = AppLocalizations.of(tester.element(find.byType(FDialog)));
    expect(find.text(l.cancel), findsNothing);
    expect(find.text(l.save), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('S'), findsNothing);
    expect(find.text(l.screenshotShortcut), findsNothing);
    expect(find.text(l.saveScreenshotShortcut), findsNothing);

    await _step(tester, _backwardKey, increase: false);
    expect(repository.value.seekBackwardSeconds, 7);
    expect(repository.value.seekForwardSeconds, 21);
    await container
        .read(settingsProvider.notifier)
        .update((settings) => settings.copyWith(subtitleFontSize: 48));
    final plus = _stepper(_forwardKey, increase: true);
    await tester.tap(plus);
    await tester.tap(plus);
    await tester.pumpAndSettle();
    expect(repository.value.seekBackwardSeconds, 7);
    expect(repository.value.seekForwardSeconds, 23);
    expect(repository.value.subtitleFontSize, 48);
    expect(find.byType(FDialog), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(FDialog), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_value(_backwardKey, 7), findsOneWidget);
    expect(_value(_forwardKey, 23), findsOneWidget);
  });

  testWidgets('wide rows align compact steppers and reserve digit width', (
    tester,
  ) async {
    final repository = MemorySettings()
      ..value = const AppSettings(
        seekBackwardSeconds: 9,
        seekForwardSeconds: 99,
      );
    await _openDialog(tester, repository, locale: const Locale('zh'));
    final content = tester.getRect(
      find.descendant(
        of: find.byType(FDialog),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    final label = tester.getRect(find.text('后退秒数（←）'));
    final minus = _stepper(_backwardKey, increase: false);
    final plus = _stepper(_backwardKey, increase: true);
    final before = tester.getRect(plus);
    expect(content.width, closeTo(400, 2));
    expect(tester.getCenter(minus).dy, closeTo(label.center.dy, 0.1));
    expect(tester.getRect(minus).left, greaterThan(label.right));
    expect(tester.getRect(minus).width, greaterThanOrEqualTo(44));
    expect(
      tester.getRect(_stepper(_forwardKey, increase: true)).left,
      before.left,
    );
    expect(find.text('9 秒'), findsOneWidget);
    await _step(tester, _backwardKey, increase: true);
    expect(find.text('10 秒'), findsOneWidget);
    expect(tester.getRect(plus), before);
  });

  testWidgets('steppers stop at one and six hundred seconds', (tester) async {
    final repository = MemorySettings()
      ..value = const AppSettings(
        seekBackwardSeconds: 2,
        seekForwardSeconds: 599,
      );
    await _openDialog(tester, repository);
    await _step(tester, _backwardKey, increase: false);
    await _step(tester, _forwardKey, increase: true);
    expect(_value(_backwardKey, 1), findsOneWidget);
    expect(_value(_forwardKey, 600), findsOneWidget);
    expect(
      tester.widget<FButton>(_stepper(_backwardKey, increase: false)).onPress,
      isNull,
    );
    expect(
      tester.widget<FButton>(_stepper(_forwardKey, increase: true)).onPress,
      isNull,
    );
    expect(repository.value.seekBackwardSeconds, 1);
    expect(repository.value.seekForwardSeconds, 600);
  });

  testWidgets('failed step retains the saved value and allows retry', (
    tester,
  ) async {
    final repository = MemorySettings()..fail = true;
    final initial = repository.value;
    final container = await _openDialog(tester, repository);
    await _step(tester, _backwardKey, increase: true);
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(_value(_backwardKey, 5), findsOneWidget);
    expect(repository.value, same(initial));
    expect(container.read(settingsProvider), same(initial));
    repository.fail = false;
    await _step(tester, _backwardKey, increase: true);
    expect(find.byType(ErrorNotice), findsNothing);
    expect(_value(_backwardKey, 6), findsOneWidget);
    expect(repository.value.seekBackwardSeconds, 6);
  });

  testWidgets('narrow dialog supports large text', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemorySettings();
    await _openDialog(tester, repository, textScale: 2);
    final label = tester.getRect(find.text('Backward seconds (←)'));
    final button = tester.getRect(_stepper(_backwardKey, increase: true));
    expect(button.top, greaterThan(label.bottom));
    await _step(tester, _backwardKey, increase: true);
    await _step(tester, _forwardKey, increase: false);
    expect(tester.takeException(), isNull);
    expect(repository.value.seekBackwardSeconds, 6);
    expect(repository.value.seekForwardSeconds, 4);
  });

  testWidgets('General settings shows editable shortcut controls inline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemorySettings();
    final container = appContainer(settingsRepository: repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    container.read(routerProvider).go('/settings');
    await settle(tester);
    await tester.tap(find.text('General'));
    await settle(tester);
    expect(find.text('Playback shortcuts'), findsOneWidget);
    expect(_value(_backwardKey, 5), findsOneWidget);
    expect(_value(_forwardKey, 5), findsOneWidget);
    expect(find.byType(FDialog), findsNothing);

    await _step(tester, _backwardKey, increase: false);
    await _step(tester, _forwardKey, increase: true);
    expect(_value(_backwardKey, 4), findsOneWidget);
    expect(_value(_forwardKey, 6), findsOneWidget);
    expect(repository.value.seekBackwardSeconds, 4);
    expect(repository.value.seekForwardSeconds, 6);
    expect(find.byType(FDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
