import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/media_server/playback_models.dart';
import 'package:sakuga/features/player/player_quality.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

Widget _app({
  required int? selected,
  required Future<void> Function(int?) onChanged,
  PlayMethod? method,
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
    child: PlayerQualityMenu(
      selected: selected,
      playMethod: method,
      enabled: enabled,
      onChanged: onChanged,
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('quality-menu')));
  await tester.pumpAndSettle();
}

void main() {
  test('formats bitrate presets', () {
    expect(formatBitrate(40000000), '40 Mbps');
    expect(formatBitrate(1500000), '1.5 Mbps');
    expect(formatBitrate(720000), '720 kbps');
    expect(
      playbackBitratePresets,
      orderedEquals([...playbackBitratePresets]..sort((a, b) => b - a)),
    );
  });

  for (final language in ['en', 'zh']) {
    testWidgets(
      'selects a cap, shows the play method and returns to maximum in $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        int? selected;
        var method = PlayMethod.directPlay;
        final requests = <int?>[];
        StateSetter? update;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return _app(
                language: language,
                selected: selected,
                method: method,
                onChanged: (bitrate) async {
                  requests.add(bitrate);
                  update!(() {
                    selected = bitrate;
                    method = bitrate == null
                        ? PlayMethod.directPlay
                        : PlayMethod.transcode;
                  });
                },
              );
            },
          ),
        );
        await _open(tester);
        final zh = language == 'zh';
        expect(find.text(zh ? '最高画质' : 'Maximum'), findsOneWidget);
        expect(find.text(zh ? '直接播放' : 'Direct play'), findsOneWidget);
        expect(find.text('720 kbps'), findsOneWidget);
        expect(
          tester
              .widget<FItem>(find.byKey(const ValueKey('quality-max')))
              .selected,
          isTrue,
        );

        // Re-selecting the active option does not renegotiate.
        await tester.tap(find.byKey(const ValueKey('quality-max')));
        await tester.pumpAndSettle();
        expect(requests, isEmpty);

        await _open(tester);
        await tester.tap(find.byKey(const ValueKey('quality-4000000')));
        await tester.pumpAndSettle();
        expect(requests, [4000000]);

        await _open(tester);
        expect(
          tester
              .widget<FItem>(find.byKey(const ValueKey('quality-4000000')))
              .selected,
          isTrue,
        );
        expect(find.text(zh ? '转码' : 'Transcoding'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('quality-max')));
        await tester.pumpAndSettle();
        expect(requests, [4000000, null]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('disabled while loading or switching', (tester) async {
    await tester.pumpWidget(
      _app(
        selected: null,
        enabled: false,
        onChanged: (_) async => fail('Disabled menu must not renegotiate'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FButton>(find.byKey(const ValueKey('quality-menu')))
          .onPress,
      isNull,
    );
    await _open(tester);
    expect(find.byType(FItem), findsNothing);
  });
}
