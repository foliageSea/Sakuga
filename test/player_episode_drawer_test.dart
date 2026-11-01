import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/features/detail/detail_providers.dart';
import 'package:sakuga/features/player/player_episode_drawer.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';
import 'package:sakuga/shared/media_widgets.dart';
import 'package:sakuga/shared/widgets.dart';

const _drawerKey = ValueKey('player-episodes-drawer');
const _closeKey = ValueKey('player-episodes-close');
const _listKey = ValueKey('player-episodes-list');

MediaItem _episode(
  String id, {
  int number = 1,
  String? name,
  MediaImageResource? poster,
}) => MediaItem(
  id: id,
  name: name ?? 'Episode $number',
  type: MediaType.episode,
  seriesId: 'series',
  parentIndexNumber: 1,
  indexNumber: number,
  runtime: const Duration(minutes: 24),
  poster: poster,
);

Finder _row(String id) => find.byKey(ValueKey('player-episode-$id'));

void main() {
  for (final size in const [
    Size(390, 844),
    Size(440, 844),
    Size(844, 390),
    Size(1280, 800),
    Size(1920, 1080),
  ]) {
    testWidgets('drawer fills the right edge at $size', (tester) async {
      final host = await _pumpHost(
        tester,
        size: size,
        episodes: [_episode('first')],
      );
      await host.open(tester);

      final bounds = tester.getRect(find.byKey(_drawerKey));
      expect(bounds.top, closeTo(0, 0.5));
      expect(bounds.bottom, closeTo(size.height, 0.5));
      expect(bounds.right, closeTo(size.width, 0.5));
      expect(bounds.width, closeTo(math.min(320, size.width - 32), 0.5));
      expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
      expect(_row('first').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(_closeKey));
      await tester.pumpAndSettle();
      expect(find.byKey(_drawerKey), findsNothing);
      expect(host.selected, isEmpty);
    });
  }

  testWidgets('rows use episode titles, metadata and their own cover headers', (
    tester,
  ) async {
    const firstPoster = MediaImageResource(
      urlTemplate: 'https://covers.example/first?width={width}',
      cacheKey: 'first-cover',
      headers: {'Authorization': 'Bearer first-token'},
    );
    const secondPoster = MediaImageResource(
      urlTemplate: 'https://covers.example/second?width={width}',
      cacheKey: 'second-cover',
      headers: {'X-Emby-Token': 'second-token'},
    );
    final host = await _pumpHost(
      tester,
      episodes: [
        _episode('first', name: 'The beginning', poster: firstPoster),
        _episode('second', number: 2, poster: secondPoster),
        _episode('missing', number: 3),
      ],
    );
    await host.open(tester);

    expect(find.text('The beginning'), findsOneWidget);
    expect(find.text('S01E01 · 24 min'), findsOneWidget);
    expect(find.text('S01E02 · 24 min'), findsOneWidget);
    for (final entry in {
      'first': firstPoster,
      'second': secondPoster,
    }.entries) {
      final cover = tester.widget<MediaImage>(
        find.descendant(of: _row(entry.key), matching: find.byType(MediaImage)),
      );
      expect(cover.url, entry.value.url(width: 320));
      expect(cover.headers, entry.value.headers);
    }
    final missingCover = tester.widget<MediaImage>(
      find.descendant(of: _row('missing'), matching: find.byType(MediaImage)),
    );
    expect(missingCover.url, isNull);
    expect(missingCover.headers, isEmpty);
    expect(
      find.descendant(
        of: _row('missing'),
        matching: find.byType(MediaPlaceholder),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('current row is selected with play icon and never switches', (
    tester,
  ) async {
    final host = await _pumpHost(
      tester,
      episodes: [_episode('first'), _episode('second', number: 2)],
    );
    await host.open(tester);

    expect(tester.widget<FItem>(_row('first')).selected, isTrue);
    expect(tester.widget<FItem>(_row('second')).selected, isFalse);
    expect(
      find.descendant(
        of: _row('first'),
        matching: find.byIcon(FLucideIcons.play),
      ),
      findsOneWidget,
    );
    await tester.tap(_row('first'));
    await tester.pumpAndSettle();
    expect(host.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting another episode dismisses before invoking callback', (
    tester,
  ) async {
    final callback = Completer<void>();
    final host = await _pumpHost(
      tester,
      episodes: [_episode('first'), _episode('second', number: 2)],
      onSelect: (_) => callback.future,
    );
    await host.open(tester);
    await tester.tap(_row('second'));
    await tester.pumpAndSettle();

    expect(find.byKey(_drawerKey), findsNothing);
    expect(host.selected, ['second']);
    expect(host.selectedAfterDismissal, [true]);
    callback.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching disables rows and updates while drawer is open', (
    tester,
  ) async {
    final host = await _pumpHost(
      tester,
      episodes: [_episode('first'), _episode('second', number: 2)],
    );
    await host.open(tester);
    host.switching.value = true;
    await tester.pumpAndSettle();

    expect(tester.widget<FItem>(_row('first')).onPress, isNull);
    expect(tester.widget<FItem>(_row('second')).onPress, isNull);
    await tester.tap(_row('second'));
    await tester.pumpAndSettle();
    expect(host.selected, isEmpty);
    expect(find.byKey(_drawerKey), findsOneWidget);

    host.switching.value = false;
    await tester.pumpAndSettle();
    expect(tester.widget<FItem>(_row('second')).onPress, isNotNull);
    await tester.tap(_row('second'));
    await tester.pumpAndSettle();
    expect(host.selected, ['second']);
    expect(find.byKey(_drawerKey), findsNothing);
  });

  testWidgets('close icon has localized semantics and does not select', (
    tester,
  ) async {
    final host = await _pumpHost(
      tester,
      locale: const Locale('zh'),
      episodes: [_episode('first')],
    );
    await host.open(tester);
    final close = find.byKey(_closeKey);
    final l10n = AppLocalizations.of(tester.element(close));
    expect(find.bySemanticsLabel(l10n.close), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(_drawerKey), findsNothing);
    expect(host.selected, isEmpty);
  });

  testWidgets('backdrop and system back dismiss without selecting', (
    tester,
  ) async {
    final host = await _pumpHost(tester, episodes: [_episode('first')]);
    await host.open(tester);
    final bounds = tester.getRect(find.byKey(_drawerKey));
    await tester.tapAt(Offset(bounds.left / 2, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(_drawerKey), findsNothing);
    expect(host.selected, isEmpty);

    await host.open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_drawerKey), findsNothing);
    expect(host.selected, isEmpty);
  });

  testWidgets('loading and empty states leave close reachable', (tester) async {
    final loading = Completer<List<MediaItem>>();
    final host = await _pumpHost(tester, load: () => loading.future);
    await tester.tap(find.text('Open'));
    // Start and finish the sheet transition without settling the spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FCircularProgress), findsOneWidget);
    expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
    expect(find.byKey(_listKey), findsNothing);

    loading.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(FCircularProgress), findsNothing);
    expect(find.text('No items'), findsOneWidget);
    expect(find.byKey(_listKey), findsNothing);
    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_drawerKey), findsNothing);
    expect(host.selected, isEmpty);
  });

  testWidgets('error can retry and render loaded episodes in the same drawer', (
    tester,
  ) async {
    var attempts = 0;
    final host = await _pumpHost(
      tester,
      load: () async {
        attempts++;
        if (attempts == 1) throw StateError('Episode request failed');
        return [_episode('first')];
      },
    );
    await host.open(tester);
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(ErrorNotice), findsNothing);
    expect(_row('first').hitTestable(), findsOneWidget);
    expect(find.byKey(_drawerKey), findsOneWidget);
    expect(host.selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps current episode and close usable in landscape', (
    tester,
  ) async {
    final host = await _pumpHost(
      tester,
      size: const Size(844, 390),
      textScale: 2,
      currentId: 'episode-60',
      episodes: List.generate(
        100,
        (i) => _episode(
          'episode-$i',
          number: i + 1,
          name:
              'A long episode title that must fit with its cover and metadata $i',
        ),
      ),
    );
    await host.open(tester);

    expect(_row('episode-60').hitTestable(), findsOneWidget);
    expect(find.byKey(_closeKey).hitTestable(), findsOneWidget);
    expect(tester.widget<FItem>(_row('episode-60')).selected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_drawerKey), findsNothing);
    expect(host.selected, isEmpty);
  });
}

class _DrawerHost {
  _DrawerHost(String? id) : currentId = ValueNotifier(id);

  final ValueNotifier<String?> currentId;
  final switching = ValueNotifier(false);
  final selected = <String>[];
  final selectedAfterDismissal = <bool>[];

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Future<_DrawerHost> _pumpHost(
  WidgetTester tester, {
  List<MediaItem> episodes = const [],
  Future<List<MediaItem>> Function()? load,
  Future<void> Function(MediaItem)? onSelect,
  String? currentId = 'first',
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final host = _DrawerHost(currentId);
  addTearDown(host.currentId.dispose);
  addTearDown(host.switching.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        seriesEpisodesProvider.overrideWith((ref, query) async {
          expect(query.userId, 'user');
          expect(query.seriesId, 'series');
          expect(query.seasonId, isNull);
          return load == null ? episodes : await load();
        }),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: FTheme(
            data: createAppTheme(
              const AppSettings(),
              brightness: Brightness.dark,
              touch: true,
            ),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FButton(
                onPress: () => showPlayerEpisodeDrawer(
                  context,
                  userId: 'user',
                  seriesId: 'series',
                  itemId: host.currentId,
                  switching: host.switching,
                  onSelect: (item) async {
                    host.selected.add(item.id);
                    host.selectedAfterDismissal.add(
                      ModalRoute.of(context)!.isCurrent,
                    );
                    if (onSelect != null) await onSelect(item);
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}
