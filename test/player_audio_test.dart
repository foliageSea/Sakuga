import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_audio.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

const _japanese = AudioTrack('2', ' Japanese ', 'jpn', codec: 'aac');
const _english = AudioTrack('5', '  ', 'eng', codec: 'ac3');

Widget _app({
  required List<AudioTrack> tracks,
  required AudioTrack selected,
  required Future<void> Function(AudioTrack) onChanged,
  bool enabled = true,
  String language = 'en',
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...FLocalizations.localizationsDelegates,
  ],
  builder: (context, child) => FTheme(
    data: createAppTheme(
      const AppSettings(),
      brightness: Brightness.dark,
      touch: false,
    ),
    child: child!,
  ),
  home: Align(
    alignment: Alignment.topRight,
    child: PlayerAudioMenu(
      tracks: tracks,
      selected: selected,
      enabled: enabled,
      onChanged: onChanged,
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('audio-menu')));
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['en', 'zh']) {
    testWidgets('switches tracks and updates selection in $language', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      AudioTrack selected = _japanese;
      StateSetter? update;
      final requests = <AudioTrack>[];
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _app(
              language: language,
              tracks: [AudioTrack.auto(), AudioTrack.no(), _japanese, _english],
              // Stream updates may contain a different object for the same ID.
              selected: AudioTrack(selected.id, null, null),
              onChanged: (track) async {
                requests.add(track);
                update!(() => selected = track);
              },
            );
          },
        ),
      );
      await _open(tester);
      expect(find.text('Japanese'), findsOneWidget);
      expect(
        find.text(language == 'zh' ? '音轨 2' : 'Audio track 2'),
        findsOneWidget,
      );
      expect(find.text('jpn · aac'), findsOneWidget);
      expect(find.text('eng · ac3'), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('audio-no')), findsOneWidget);
      expect(
        tester.widget<FItem>(find.byKey(const ValueKey('audio-2'))).selected,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('audio-5')));
      await tester.pumpAndSettle();
      expect(requests.single, same(_english));
      expect(find.byKey(const ValueKey('audio-5')), findsNothing);
      await _open(tester);
      expect(
        tester.widget<FItem>(find.byKey(const ValueKey('audio-5'))).selected,
        isTrue,
      );
      expect(
        tester.widget<FItem>(find.byKey(const ValueKey('audio-2'))).selected,
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('audio-no')));
      await tester.pumpAndSettle();
      expect(requests.last.id, 'no');
      await _open(tester);
      expect(
        tester.widget<FItem>(find.byKey(const ValueKey('audio-no'))).selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('audio-auto')));
      await tester.pumpAndSettle();
      expect(requests.last.id, 'auto');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'disables unavailable tracks and enables newly discovered tracks',
    (tester) async {
      var calls = 0;
      for (final tracks in <List<AudioTrack>>[
        [],
        [AudioTrack.auto(), AudioTrack.no()],
      ]) {
        await tester.pumpWidget(
          _app(
            tracks: tracks,
            selected: AudioTrack.auto(),
            onChanged: (_) async => calls++,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FButton>(find.byKey(const ValueKey('audio-menu')))
              .onPress,
          isNull,
        );
        await _open(tester);
        expect(find.byType(FItem), findsNothing);
      }
      await tester.pumpWidget(
        _app(
          tracks: const [_japanese],
          selected: AudioTrack.auto(),
          onChanged: (_) async => calls++,
        ),
      );
      await tester.pumpAndSettle();
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('audio-2')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disables selection while media is loading or switching', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        tracks: const [_japanese, _english],
        selected: _japanese,
        enabled: false,
        onChanged: (_) async => fail('Disabled menu must not change audio'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FButton>(find.byKey(const ValueKey('audio-menu'))).onPress,
      isNull,
    );
    await _open(tester);
    expect(find.byType(FItem), findsNothing);
  });
}
