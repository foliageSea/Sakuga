import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/library/library_providers.dart';

import 'fakes.dart';
import 'widget_test.dart' show appContainer, settle;

const _a = ServerProfile(id: 'a', name: 'Server A', baseUrl: 'http://a.test');
const _b = ServerProfile(id: 'b', name: 'Server B', baseUrl: 'http://b.test');
const _c = ServerProfile(id: 'c', name: 'Server C', baseUrl: 'http://c.test');

class _PendingServers extends MemoryServerRepository {
  final saved = Completer<void>();
  int saves = 0;

  @override
  Future<void> save(List<ServerProfile> servers) async {
    saves++;
    await saved.future;
    await super.save(servers);
  }
}

void main() {
  test(
    'selection persists with credentials and deletion selects the next server',
    () async {
      final b = _b.copyWith(apiKey: 'b-key');
      final repository = MemoryServerRepository()..items = [_a, b, _c];
      final container = appContainer(serverRepository: repository);
      addTearDown(container.dispose);
      await container.read(serversProvider.future);

      await container.read(serversProvider.notifier).setActive('b');
      expect(container.read(activeServerProvider), same(b));
      expect(repository.items.map((s) => s.id), ['b', 'a', 'c']);
      expect(repository.items.first.apiKey, 'b-key');

      final reopened = appContainer(serverRepository: repository);
      addTearDown(reopened.dispose);
      await reopened.read(serversProvider.future);
      expect(reopened.read(activeServerProvider)?.id, 'b');
      await reopened.read(serversProvider.notifier).remove('b');
      expect(reopened.read(activeServerProvider)?.id, 'a');
      await reopened.read(serversProvider.notifier).remove('a');
      await reopened.read(serversProvider.notifier).remove('c');
      expect(reopened.read(activeServerProvider), isNull);
    },
  );

  test('save failure preserves current selection; active and unknown IDs are no-ops', () async {
    final repository = MemoryServerRepository()..items = [_a, _b];
    final container = appContainer(serverRepository: repository);
    addTearDown(container.dispose);
    await container.read(serversProvider.future);
    repository.fail = true;
    final notifier = container.read(serversProvider.notifier);
    await notifier.setActive('a');
    await notifier.setActive('missing');
    await expectLater(notifier.setActive('b'), throwsException);
    expect(container.read(activeServerProvider)?.id, 'a');
    expect(repository.items, [_a, _b]);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'switch server opens its library and updates current status at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _PendingServers()..items = [_a, _b];
        final container = appContainer(serverRepository: repository);
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const SakugaApp(),
          ),
        );
        final router = container.read(routerProvider);
        router.go('/library/old-server-item');
        await settle(tester);
        router.go('/settings?tab=servers');
        await settle(tester);
        final a = find.byKey(const ValueKey('switch-server-a'));
        final b = find.byKey(const ValueKey('switch-server-b'));
        expect(tester.widget<FButton>(a).onPress, isNull);
        expect(
          find.descendant(of: a, matching: find.byIcon(FLucideIcons.check)),
          findsOneWidget,
        );
        await tester.tap(b);
        await tester.pump();
        expect(tester.widget<FButton>(b).onPress, isNull);
        expect(
          tester
              .widget<FButton>(find.byKey(const ValueKey('add-server')))
              .onPress,
          isNull,
        );
        expect(repository.saves, 1);
        expect(container.read(activeServerProvider)?.id, 'a');
        repository.saved.complete();
        await settle(tester);
        expect(container.read(activeServerProvider)?.id, 'b');
        expect(router.routeInformationProvider.value.uri.path, '/library');
        expect(find.text('Add an API key for this server.'), findsOneWidget);
        router.go('/settings');
        await settle(tester);
        expect(
          find.descendant(of: b, matching: find.byIcon(FLucideIcons.check)),
          findsOneWidget,
        );
        expect(tester.widget<FButton>(a).onPress, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
      },
    );
  }

  testWidgets('failed switch stays in settings and supports retry', (
    tester,
  ) async {
    final repository = MemoryServerRepository()
      ..items = [_a, _b]
      ..fail = true;
    final container = appContainer(serverRepository: repository);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    final router = container.read(routerProvider);
    router.go('/settings');
    await settle(tester);
    final b = find.byKey(const ValueKey('switch-server-b'));
    await tester.tap(b);
    await settle(tester);
    expect(container.read(activeServerProvider)?.id, 'a');
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(
      find.textContaining('Could not save or read local data.'),
      findsOneWidget,
    );
    repository.fail = false;
    await tester.tap(b);
    await settle(tester);
    expect(container.read(activeServerProvider)?.id, 'b');
    expect(router.routeInformationProvider.value.uri.path, '/library');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
