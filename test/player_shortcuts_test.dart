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
const _saveKey = ValueKey('player-shortcuts-save');
const _cancelKey = ValueKey('player-shortcuts-cancel');

Finder _input(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(EditableText));

String _text(WidgetTester tester, Key key) =>
    tester.widget<EditableText>(_input(key)).controller.text;

Future<ProviderContainer> _openDialog(
  WidgetTester tester,
  MemorySettings repository, {
  double textScale = 1,
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
        locale: const Locale('en'),
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

Future<void> _save(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(_saveKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_saveKey));
  await tester.pumpAndSettle();
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

  testWidgets('save persists both intervals only after explicit submission', (
    tester,
  ) async {
    final repository = MemorySettings()
      ..value = const AppSettings(
        seekBackwardSeconds: 8,
        seekForwardSeconds: 21,
      );
    final container = await _openDialog(tester, repository);
    expect(_text(tester, _backwardKey), '8');
    expect(_text(tester, _forwardKey), '21');
    final l = AppLocalizations.of(tester.element(find.byType(FDialog)));
    expect(find.text(l.screenshotShortcut), findsOneWidget);
    await tester.enterText(_input(_backwardKey), '1');
    await tester.enterText(_input(_forwardKey), '600');
    expect(repository.value.seekBackwardSeconds, 8);
    expect(repository.value.seekForwardSeconds, 21);
    // Saving must preserve settings changed elsewhere while this dialog is open.
    await container
        .read(settingsProvider.notifier)
        .update((settings) => settings.copyWith(subtitleFontSize: 48));
    await _save(tester);
    expect(find.byType(FDialog), findsNothing);
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode((await repository.load()).toJson()))
          as Map<String, dynamic>,
    );
    expect(restored.seekBackwardSeconds, 1);
    expect(restored.seekForwardSeconds, 600);
    expect(restored.subtitleFontSize, 48);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_text(tester, _backwardKey), '1');
    expect(_text(tester, _forwardKey), '600');
  });

  testWidgets('invalid input remains editable and cannot save either field', (
    tester,
  ) async {
    final repository = MemorySettings();
    final initial = repository.value;
    await _openDialog(tester, repository);
    final l = AppLocalizations.of(tester.element(find.byType(FDialog)));
    await tester.enterText(_input(_forwardKey), '37');
    for (final invalid in ['', '0', '-1', '601', '1.5', 'abc', '0x10']) {
      await tester.enterText(_input(_backwardKey), invalid);
      await _save(tester);
      expect(find.text(l.seekSecondsInvalid), findsOneWidget);
      expect(_text(tester, _backwardKey), invalid);
      expect(_text(tester, _forwardKey), '37');
      expect(repository.value, same(initial));
    }
    await tester.enterText(_input(_backwardKey), '12');
    await tester.enterText(_input(_forwardKey), '4.0');
    await _save(tester);
    expect(find.text(l.seekSecondsInvalid), findsOneWidget);
    expect(_text(tester, _backwardKey), '12');
    expect(_text(tester, _forwardKey), '4.0');
    expect(repository.value, same(initial));
    await tester.enterText(_input(_forwardKey), '25');
    await _save(tester);
    expect(find.byType(FDialog), findsNothing);
    expect(repository.value.seekBackwardSeconds, 12);
    expect(repository.value.seekForwardSeconds, 25);
  });

  testWidgets('cancel discards unsaved edits', (tester) async {
    final repository = MemorySettings();
    final initial = repository.value;
    final container = await _openDialog(tester, repository);
    await tester.enterText(_input(_backwardKey), '90');
    await tester.enterText(_input(_forwardKey), '180');
    await tester.tap(find.byKey(_cancelKey));
    await tester.pumpAndSettle();
    expect(find.byType(FDialog), findsNothing);
    expect(repository.value, same(initial));
    expect(container.read(settingsProvider), same(initial));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_text(tester, _backwardKey), '5');
    expect(_text(tester, _forwardKey), '5');
  });

  testWidgets('failed save keeps edits and allows retry', (tester) async {
    final repository = MemorySettings()..fail = true;
    final initial = repository.value;
    final container = await _openDialog(tester, repository);
    await tester.enterText(_input(_backwardKey), '15');
    await tester.enterText(_input(_forwardKey), '45');
    await _save(tester);
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(_text(tester, _backwardKey), '15');
    expect(_text(tester, _forwardKey), '45');
    expect(repository.value, same(initial));
    expect(container.read(settingsProvider), same(initial));
    repository.fail = false;
    await _save(tester);
    expect(find.byType(FDialog), findsNothing);
    expect(repository.value.seekBackwardSeconds, 15);
    expect(repository.value.seekForwardSeconds, 45);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow dialog supports large text and scrolls to save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemorySettings();
    await _openDialog(tester, repository, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_input(_backwardKey));
    await tester.enterText(_input(_backwardKey), '20');
    await tester.ensureVisible(_input(_forwardKey));
    await tester.enterText(_input(_forwardKey), '40');
    await _save(tester);
    expect(tester.takeException(), isNull);
    expect(repository.value.seekBackwardSeconds, 20);
    expect(repository.value.seekForwardSeconds, 40);
  });

  testWidgets('General settings opens the shared shortcut dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = appContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    container.read(routerProvider).go('/settings');
    await settle(tester);
    await tester.tap(find.text('General'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('player-shortcuts-settings')));
    await settle(tester);
    expect(find.byKey(_backwardKey), findsOneWidget);
    expect(find.byKey(_forwardKey), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_cancelKey));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
