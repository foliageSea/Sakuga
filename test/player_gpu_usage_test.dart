import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/features/player/player_gpu_usage.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

Widget _wrap(Widget child) {
  final theme = createAppTheme(
    const AppSettings(),
    brightness: Brightness.dark,
    touch: false,
  );
  return MaterialApp(
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...FLocalizations.localizationsDelegates,
    ],
    builder: (context, inner) => FTheme(
      data: theme,
      child: FToaster(child: FTooltipGroup(child: inner!)),
    ),
    home: Center(child: child),
  );
}

void main() {
  testWidgets('displays and updates GPU usage while mounted', (tester) async {
    var current = 37 as int?;
    var reads = 0;
    var showBadge = true;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBadge)
                PlayerGpuUsage(
                  pollInterval: const Duration(seconds: 2),
                  readPercentage: () async {
                    reads++;
                    return current;
                  },
                ),
              GestureDetector(
                key: const ValueKey('toggle-sr'),
                onTap: () => setState(() => showBadge = !showBadge),
                child: const Text('Toggle'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('player-gpu-usage')), findsOneWidget);
    expect(find.text('GPU 37%'), findsOneWidget);
    expect(reads, 1);

    current = 74;
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('GPU 74%'), findsOneWidget);
    expect(reads, 2);

    // Turning off super resolution unmounts the widget and stops polling.
    await tester.tap(find.byKey(const ValueKey('toggle-sr')));
    await tester.pump();
    expect(find.byKey(const ValueKey('player-gpu-usage')), findsNothing);

    final readsAfterUnmount = reads;
    await tester.pump(const Duration(seconds: 6));
    expect(reads, readsAfterUnmount);
  });

  testWidgets('renders nothing when GPU counter is unavailable', (tester) async {
    await tester.pumpWidget(
      _wrap(
        PlayerGpuUsage(
          readPercentage: () async => null,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('player-gpu-usage')), findsNothing);
    expect(tester.getSize(find.byType(PlayerGpuUsage)), Size.zero);
  });

  testWidgets('pauses polling in background or offstage TickerMode', (
    tester,
  ) async {
    var current = 25;
    var reads = 0;
    var tickerEnabled = true;
    Future<int?> readUsage() async {
      reads++;
      return current;
    }

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TickerMode(
                enabled: tickerEnabled,
                child: PlayerGpuUsage(
                  pollInterval: const Duration(seconds: 2),
                  readPercentage: readUsage,
                ),
              ),
              GestureDetector(
                key: const ValueKey('toggle-ticker'),
                onTap: () => setState(() => tickerEnabled = !tickerEnabled),
                child: const Text('Ticker'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('GPU 25%'), findsOneWidget);
    expect(reads, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 6));
    expect(reads, 1);

    current = 63;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('GPU 63%'), findsOneWidget);
    expect(reads, 2);

    // Covering the route (e.g. fullscreen route pushed above) disables TickerMode.
    await tester.tap(find.byKey(const ValueKey('toggle-ticker')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(reads, 2);

    current = 81;
    await tester.tap(find.byKey(const ValueKey('toggle-ticker')));
    await tester.pump();
    await tester.pump();
    expect(find.text('GPU 81%'), findsOneWidget);
    expect(reads, 3);
  });
}
