import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/data/media_server/server_config.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/settings/server_config_files.dart';

import 'fakes.dart';
import 'widget_test.dart' show appContainer, settle;

const _existing = ServerProfile(
  id: 'existing',
  name: 'Existing server',
  baseUrl: 'https://example.test/jellyfin',
  apiKey: 'existing-key',
);
final _ugreen = ServerProfile(
  id: 'old-id',
  name: 'UGREEN NAS',
  baseUrl: 'https://nas.test:9443',
  type: MediaServerType.ugreen,
  username: 'alice',
  userId: 'user-id',
  accessToken: 'secret-token',
  deviceId: 'device-id',
  remoteServerId: 'remote-id',
  certificateFingerprint: 'ab' * 32,
);

class _Files implements ServerConfigFiles {
  Uint8List? picked;
  Uint8List? exported;

  @override
  Future<Uint8List?> pick() async => picked;

  @override
  Future<ServerConfigExportResult> export(
    Uint8List bytes, {
    Rect? sharePositionOrigin,
  }) async {
    exported = bytes;
    return ServerConfigExportResult.saved;
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _chooseConfigAction(WidgetTester tester, String action) async {
  await tester.tap(_key('server-config-menu'));
  await settle(tester);
  await tester.tap(_key(action));
  await settle(tester);
}

Future<void> _openSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SakugaApp()),
  );
  container.read(routerProvider).go('/settings?tab=servers');
  await settle(tester);
}

void main() {
  test(
    'config preserves server order and only exports credentials by opt-in',
    () {
      final safe = ServerConfig.encode([
        _existing,
        _ugreen,
      ], includeCredentials: false);
      final text = utf8.decode(safe);
      for (final key in [
        'apiKey',
        'accessToken',
        'deviceId',
        'remoteServerId',
        'password',
        'old-id',
      ]) {
        expect(text, isNot(contains(key)));
      }
      final servers = ServerConfig.decode(safe);
      expect(servers.map((s) => s.name), [_existing.name, _ugreen.name]);
      expect(
        servers.last.certificateFingerprint,
        _ugreen.certificateFingerprint,
      );
      expect(servers.last.username, 'alice');
      expect(servers.last.accessToken, isEmpty);
      final full = ServerConfig.decode(
        ServerConfig.encode([_existing, _ugreen], includeCredentials: true),
      );
      expect(full.first.apiKey, _existing.apiKey);
      expect(full.last.accessToken, _ugreen.accessToken);
      expect(full.last.deviceId, _ugreen.deviceId);
      expect(full.last.remoteServerId, _ugreen.remoteServerId);
    },
  );

  test('rejects malformed, oversized, and unsupported files or entries', () {
    final valid = utf8.decode(
      ServerConfig.encode([_existing], includeCredentials: false),
    );
    for (final text in [
      'not JSON',
      '[]',
      valid.replaceFirst('"version": 1', '"version": 2'),
      valid.replaceFirst('"jellyfin"', '"unknown"'),
      valid.replaceFirst('"Existing server"', 'null'),
      valid.replaceFirst(_existing.baseUrl, 'ftp://example.test'),
      valid.replaceFirst(
        _existing.baseUrl,
        'https://name:password@example.test',
      ),
    ]) {
      expect(
        () => ServerConfig.decode(utf8.encode(text)),
        throwsFormatException,
      );
    }
    expect(
      () => ServerConfig.decode(Uint8List(serverConfigMaxBytes + 1)),
      throwsFormatException,
    );
  });

  test('merge skips duplicates, preserves the active profile, and handles save failure', () async {
    final repository = MemoryServerRepository()..items = [_existing];
    final container = appContainer(serverRepository: repository);
    addTearDown(container.dispose);
    await container.read(serversProvider.future);
    final notifier = container.read(serversProvider.notifier);
    final duplicate = _existing.copyWith(
      name: 'Renamed',
      baseUrl: 'https://EXAMPLE.test:443/jellyfin/',
      apiKey: 'replacement-key',
    );
    final incoming = [
      duplicate,
      _ugreen,
      _ugreen.copyWith(name: 'Duplicate NAS'),
    ];
    repository.fail = true;
    await expectLater(notifier.importConfig(incoming), throwsException);
    expect(container.read(serversProvider).requireValue, [_existing]);
    repository.fail = false;
    final result = await notifier.importConfig(incoming);
    expect(result.added.single.id, isNot(anyOf(_existing.id, _ugreen.id)));
    expect(result.skipped, [duplicate, incoming.last]);
    expect(repository.items, [_existing, result.added.single]);
    final repeated = await notifier.importConfig(incoming);
    expect(repeated.added, isEmpty);
    expect(repeated.skipped, incoming);
  });

  testWidgets(
    'file actions are hidden in the menu; import previews before merging',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = _Files()
        ..picked = ServerConfig.encode([
          _existing,
          _ugreen,
        ], includeCredentials: false);
      final repository = MemoryServerRepository()..items = [_existing];
      final container = appContainer(
        serverRepository: repository,
        serverConfigFiles: files,
      );
      addTearDown(container.dispose);
      await _openSettings(tester, container);
      expect(_key('switch-server-${_existing.id}'), findsOneWidget);
      expect(_key('import-servers').hitTestable(), findsNothing);
      expect(_key('export-servers').hitTestable(), findsNothing);
      await tester.tap(_key('server-config-menu'));
      await settle(tester);
      expect(_key('switch-server-${_existing.id}'), findsOneWidget);
      expect(_key('add-server'), findsOneWidget);
      expect(_key('export-servers'), findsOneWidget);
      await tester.tap(_key('import-servers'));
      await settle(tester);
      expect(find.text('To add: 1'), findsOneWidget);
      expect(find.text('Duplicates to skip: 1'), findsOneWidget);
      expect(repository.items, [_existing]);
      await tester.tap(_key('confirm-server-config'));
      await settle(tester);
      expect(repository.items.map((s) => s.name), [
        _existing.name,
        _ugreen.name,
      ]);
      expect(repository.items.last.accessToken, isEmpty);
      expect(_key('import-servers').hitTestable(), findsNothing);
      expect(find.text(_ugreen.name), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets(
    'invalid import does not change servers; credential export requires opt-in',
    (tester) async {
      final files = _Files()..picked = utf8.encode('invalid');
      final repository = MemoryServerRepository()..items = [_existing];
      final container = appContainer(
        serverRepository: repository,
        serverConfigFiles: files,
      );
      addTearDown(container.dispose);
      await _openSettings(tester, container);
      await _chooseConfigAction(tester, 'import-servers');
      expect(find.textContaining('Invalid, oversized'), findsOneWidget);
      expect(repository.items, [_existing]);

      await _chooseConfigAction(tester, 'export-servers');
      await tester.tap(_key('confirm-server-config'));
      await settle(tester);
      expect(ServerConfig.decode(files.exported!).single.apiKey, isEmpty);

      await _chooseConfigAction(tester, 'export-servers');
      await tester.tap(find.text('Include login credentials'));
      await settle(tester);
      expect(find.textContaining('unencrypted API keys'), findsOneWidget);
      await tester.tap(_key('confirm-server-config'));
      await settle(tester);
      expect(
        ServerConfig.decode(files.exported!).single.apiKey,
        _existing.apiKey,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
