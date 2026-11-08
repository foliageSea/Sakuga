import 'dart:async';

import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/emby/emby_auth.dart';
import 'package:sakuga/data/jellyfin/jellyfin_auth.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/media_server_client.dart';
import 'package:sakuga/data/media_server/media_server_factory.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_probe.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/settings/servers_section.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

const _saved = ServerProfile(
  id: 'saved',
  name: 'Home',
  baseUrl: 'http://media.example',
  type: MediaServerType.jellyfin,
  accessToken: 'old-token',
  userId: 'alice-id',
  username: 'alice',
  deviceId: 'device',
  remoteServerId: 'remote',
);

class _Auth extends Fake implements JellyfinAuthService {
  int calls = 0;
  String? lastPassword;
  String? lastUsername;
  String? lastUrl;
  String? lastDevice;
  Object? error;
  Completer<EmbyAuthResult>? pending;

  @override
  Future<EmbyAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    calls++;
    lastPassword = password;
    lastUsername = username;
    lastUrl = baseUrl;
    lastDevice = deviceId;
    if (error != null) throw error!;
    return pending?.future ?? result(username);
  }

  EmbyAuthResult result([String username = 'alice']) => EmbyAuthResult(
    accessToken: 'new-token',
    userId: '$username-id',
    username: username,
    remoteServerId: 'remote',
  );
}

class _Probe implements ServerProbe {
  int calls = 0;
  String? lastKey;

  @override
  Future<ServerProbeResult> probe(String rawUrl, {String apiKey = ''}) async {
    calls++;
    lastKey = apiKey;
    return const ServerProbeResult(
      name: 'Jellyfin',
      version: '10.10',
      id: 'remote',
    );
  }
}

class _Session extends Fake implements MediaServerClient {
  int calls = 0;
  Object? error;
  @override
  Future<List<MediaUser>> users() async {
    calls++;
    if (error != null) throw error!;
    return const [MediaUser(id: 'alice-id', name: 'alice')];
  }
}

class _Factory extends MediaServerFactory {
  _Factory(this.session);
  final _Session session;
  @override
  MediaServerClient createClient(ServerProfile server) => session;
}

Future<void> _pump(
  WidgetTester tester,
  MemoryServerRepository repository,
  _Auth auth, {
  _Session? session,
  _Probe? probe,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1100, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serverRepositoryProvider.overrideWithValue(repository),
        if (probe != null)
          serverProbeProvider(MediaServerType.jellyfin)
              .overrideWithValue(probe),
        jellyfinAuthProvider.overrideWithValue(auth),
        jellyfinDeviceIdProvider.overrideWith((ref) async => 'device'),
        mediaServerFactoryProvider.overrideWithValue(
          _Factory(session ?? _Session()),
        ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: FTheme.neutral.light.touch,
          child: FTooltipGroup(child: child!),
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: ServersSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));
Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  await tester.enterText(
    find.descendant(of: _key(key), matching: find.byType(EditableText)),
    value,
  );
  await tester.pump();
}

Future<void> _add(WidgetTester tester) async {
  await _tap(tester, 'add-server');
  expect(_key('server-password'), findsOneWidget);
  expect(_key('server-auth-method'), findsOneWidget);
  expect(_key('server-api-key'), findsNothing);
  await _enter(tester, 'server-name', 'Home');
  await _enter(tester, 'server-url', 'media.example');
  await _enter(tester, 'server-username', 'alice');
  await _enter(tester, 'server-password', ' password ');
}

Future<void> _edit(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Edit'));
  await tester.pumpAndSettle();
}

Future<void> _mode(WidgetTester tester, String label) async {
  await _tap(tester, 'server-auth-method');
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  const apiProfile = ServerProfile(
    id: 'api-saved',
    name: 'API Home',
    baseUrl: 'http://media.example',
    apiKey: 'legacy-key',
  );

  testWidgets('saved API key profile retains its mode and uses the probe', (
    tester,
  ) async {
    final repo = MemoryServerRepository()..items = [apiProfile];
    final auth = _Auth();
    final probe = _Probe();
    final session = _Session();
    await _pump(tester, repo, auth, probe: probe, session: session);
    await _edit(tester);
    expect(_key('server-api-key'), findsOneWidget);
    expect(_key('server-password'), findsNothing);
    await _tap(tester, 'server-test');
    expect(probe.calls, 1);
    expect(probe.lastKey, 'legacy-key');
    expect(auth.calls, 0);
    expect(session.calls, 0);
    await _enter(tester, 'server-name', 'Renamed API');
    await _tap(tester, 'server-save');
    expect(repo.items.single.id, apiProfile.id);
    expect(repo.items.single.apiKey, 'legacy-key');
    expect(repo.items.single.accessToken, isEmpty);
    expect(repo.items.single.username, isEmpty);
  });

  testWidgets('switching API key to account clears key and replaces identity', (
    tester,
  ) async {
    final repo = MemoryServerRepository()..items = [apiProfile];
    final auth = _Auth();
    await _pump(tester, repo, auth);
    await _edit(tester);
    await _mode(tester, 'Account/password');
    expect(_key('server-api-key'), findsNothing);
    await _enter(tester, 'server-username', 'alice');
    await _enter(tester, 'server-password', 'secret');
    await _tap(tester, 'server-save');
    expect(auth.calls, 1);
    expect(repo.items.single.id, isNot(apiProfile.id));
    expect(repo.items.single.apiKey, isEmpty);
    expect(repo.items.single.accessToken, 'new-token');
    expect(repo.items.single.type, MediaServerType.jellyfin);
  });

  testWidgets('switching account to API key clears all account fields', (
    tester,
  ) async {
    final repo = MemoryServerRepository()..items = [_saved];
    final auth = _Auth();
    await _pump(tester, repo, auth);
    await _edit(tester);
    await _enter(tester, 'server-password', 'secret');
    await _mode(tester, 'API key');
    expect(_key('server-password'), findsNothing);
    await _enter(tester, 'server-api-key', 'replacement-key');
    await _tap(tester, 'server-save');
    final saved = repo.items.single;
    expect(auth.calls, 0);
    expect(saved.id, isNot(_saved.id));
    expect(saved.apiKey, 'replacement-key');
    expect([
      saved.accessToken,
      saved.userId,
      saved.username,
      saved.deviceId,
      saved.remoteServerId,
    ], everyElement(isEmpty));
  });

  testWidgets('changing mode during login discards the pending session', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final pending = Completer<EmbyAuthResult>();
    final auth = _Auth()..pending = pending;
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-test');
    await _mode(tester, 'API key');
    pending.complete(auth.result());
    await tester.pumpAndSettle();
    expect(_key('server-test-result'), findsNothing);
    await _enter(tester, 'server-api-key', 'replacement-key');
    await _tap(tester, 'server-save');
    expect(auth.calls, 1);
    expect(repo.items.single.apiKey, 'replacement-key');
    expect(repo.items.single.accessToken, isEmpty);
  });

  testWidgets('switching back to account clears typed credentials', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final auth = _Auth();
    await _pump(tester, repo, auth);
    await _add(tester);
    await _mode(tester, 'API key');
    await _enter(tester, 'server-api-key', 'temporary-key');
    await _mode(tester, 'Account/password');
    await _tap(tester, 'server-save');
    expect(find.text('Enter a username.'), findsOneWidget);
    expect(auth.calls, 0);
    await _enter(tester, 'server-username', 'bob');
    await _tap(tester, 'server-save');
    expect(auth.lastPassword, '');
    expect(repo.items.single.apiKey, isEmpty);
    expect(repo.items.single.username, 'bob');
  });

  testWidgets('Jellyfin Save authenticates before persisting an account', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final auth = _Auth();
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-save');
    expect(auth.calls, 1);
    expect(auth.lastPassword, ' password ');
    expect(auth.lastUrl, 'http://media.example');
    expect(auth.lastDevice, 'device');
    expect(repo.items.single.accessToken, 'new-token');
    expect(repo.items.single.userId, 'alice-id');
    expect(repo.items.single.apiKey, isEmpty);
    expect(find.text('Jellyfin · alice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Test authenticates without saving and Save reuses its result', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final auth = _Auth();
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-test');
    expect(auth.calls, 1);
    expect(repo.items, isEmpty);
    expect(_key('server-test-result'), findsOneWidget);
    await _tap(tester, 'server-save');
    expect(auth.calls, 1);
    expect(repo.items.single.accessToken, 'new-token');
  });

  testWidgets('failed credentials cannot save and show relogin guidance', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final auth = _Auth()..error = const AppException(FailureKind.auth);
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-save');
    expect(repo.items, isEmpty);
    expect(find.textContaining('Enter your password and save'), findsOneWidget);
    expect(_key('server-password'), findsOneWidget);
  });

  testWidgets('name-only edit preserves the session and identity', (
    tester,
  ) async {
    final repo = MemoryServerRepository()..items = [_saved];
    final auth = _Auth();
    await _pump(tester, repo, auth);
    await _edit(tester);
    await _enter(tester, 'server-name', 'Renamed');
    await _tap(tester, 'server-save');
    final saved = repo.items.single;
    expect(auth.calls, 0);
    expect(saved.id, _saved.id);
    expect(saved.name, 'Renamed');
    expect(saved.accessToken, _saved.accessToken);
    expect(saved.deviceId, _saved.deviceId);
    expect(saved.remoteServerId, _saved.remoteServerId);
  });

  for (final field in ['server-url', 'server-username']) {
    testWidgets(
      'changing $field reauthenticates and replaces the old identity',
      (tester) async {
        final repo = MemoryServerRepository()..items = [_saved];
        final auth = _Auth();
        await _pump(tester, repo, auth);
        await _edit(tester);
        await _enter(
          tester,
          field,
          field == 'server-url' ? 'other.example' : 'bob',
        );
        await _enter(tester, 'server-password', 'secret');
        await _tap(tester, 'server-save');
        expect(auth.calls, 1);
        expect(repo.items, hasLength(1));
        expect(repo.items.single.id, isNot(_saved.id));
        expect(repo.items.single.accessToken, 'new-token');
      },
    );
  }

  testWidgets(
    'entering a password refreshes the session with the same identity',
    (tester) async {
      final repo = MemoryServerRepository()..items = [_saved];
      final auth = _Auth();
      await _pump(tester, repo, auth);
      await _edit(tester);
      await _enter(tester, 'server-password', 'secret');
      await _tap(tester, 'server-save');
      expect(auth.calls, 1);
      expect(repo.items.single.id, _saved.id);
      expect(repo.items.single.accessToken, 'new-token');
    },
  );

  testWidgets('existing Test validates the user session and allows relogin', (
    tester,
  ) async {
    final repo = MemoryServerRepository()..items = [_saved];
    final auth = _Auth();
    final request = RequestOptions(path: '/emby/Users/alice-id');
    final session = _Session()
      ..error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 401),
        type: DioExceptionType.badResponse,
      );
    await _pump(tester, repo, auth, session: session);
    await _edit(tester);
    await _tap(tester, 'server-test');
    expect(session.calls, 1);
    expect(auth.calls, 0);
    expect(find.textContaining('session expired'), findsOneWidget);
    expect(repo.items.single.accessToken, 'old-token');
    // A revoked passwordless account must authenticate even with an empty field.
    await _tap(tester, 'server-save');
    expect(auth.calls, 1);
    expect(auth.lastPassword, '');
    expect(repo.items.single.accessToken, 'new-token');
  });

  testWidgets('pending login prevents duplicates and ignores edited inputs', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final pending = Completer<EmbyAuthResult>();
    final auth = _Auth()..pending = pending;
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-test');
    await _tap(tester, 'server-test');
    await _tap(tester, 'server-save');
    expect(auth.calls, 1);
    await _enter(tester, 'server-username', 'bob');
    pending.complete(auth.result());
    await tester.pumpAndSettle();
    expect(_key('server-test-result'), findsNothing);
    expect(repo.items, isEmpty);
    auth.pending = null;
    await _tap(tester, 'server-save');
    expect(auth.calls, 2);
    expect(repo.items.single.username, 'bob');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissed editor ignores a pending authentication response', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final pending = Completer<EmbyAuthResult>();
    final auth = _Auth()..pending = pending;
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-test');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    pending.complete(auth.result());
    await tester.pumpAndSettle();
    expect(repo.items, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back during Save ignores authentication before route disposal', (
    tester,
  ) async {
    final repo = MemoryServerRepository();
    final pending = Completer<EmbyAuthResult>();
    final auth = _Auth()..pending = pending;
    await _pump(tester, repo, auth);
    await _add(tester);
    await _tap(tester, 'server-save');
    final context = tester.element(_key('server-password'));
    Navigator.of(context).pop();
    pending.complete(auth.result());
    await tester.pumpAndSettle();
    expect(repo.items, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'storage failure leaves editor open and retains login for retry',
    (tester) async {
      final repo = MemoryServerRepository()..fail = true;
      final auth = _Auth();
      await _pump(tester, repo, auth);
      await _add(tester);
      await _tap(tester, 'server-save');
      expect(repo.items, isEmpty);
      expect(_key('server-save'), findsOneWidget);
      repo.fail = false;
      await _tap(tester, 'server-save');
      expect(auth.calls, 1);
      expect(repo.items.single.accessToken, 'new-token');
    },
  );

  testWidgets('Jellyfin credentials are localized in Chinese', (tester) async {
    final repo = MemoryServerRepository()..items = [_saved];
    await _pump(tester, repo, _Auth(), locale: 'zh');
    await tester.tap(find.bySemanticsLabel('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('服务器类型'), findsOneWidget);
    expect(find.text('认证方式'), findsOneWidget);
    expect(find.text('账号/密码'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
  });
}
