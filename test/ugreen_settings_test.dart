import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/data/media_browser/media_browser_auth.dart';
import 'package:sakuga/data/media_server/media_server_factory.dart';
import 'package:sakuga/data/ugreen/ugreen_auth.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/settings/servers_section.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

class _Auth extends Fake implements UgreenAuthService {
  final logins = <(String, String, String, String)>[];

  @override
  Future<MediaBrowserAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
    String fingerprint = '',
  }) async {
    logins.add((baseUrl, username, password, fingerprint));
    return MediaBrowserAuthResult(
      accessToken: 'token-${logins.length}',
      userId: 'user-1',
      username: username,
      remoteServerId: 'nas-1',
    );
  }
}

class _Factory extends MediaServerFactory {
  int validations = 0;

  @override
  FakeMediaServerClient createClient(ServerProfile server) {
    validations++;
    return FakeMediaServerClient(server: server);
  }
}

void main() {
  testWidgets(
    'UGREEN validates access before saving and reauthenticates on pin change',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      final repo = MemoryServerRepository();
      final factory = _Factory();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverRepositoryProvider.overrideWithValue(repo),
            ugreenAuthProvider.overrideWithValue(auth),
            ugreenDeviceIdProvider.overrideWith((ref) async => 'test-device'),
            mediaServerFactoryProvider.overrideWithValue(factory),
          ],
          child: MaterialApp(
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

      Finder key(String id) => find.byKey(ValueKey(id));
      Future<void> tap(String id) async {
        await tester.ensureVisible(key(id));
        await tester.tap(key(id));
        await tester.pumpAndSettle();
      }

      Future<void> enter(String id, String text) async {
        await tester.enterText(
          find.descendant(of: key(id), matching: find.byType(EditableText)),
          text,
        );
        await tester.pump();
      }

      await tap('add-server');
      await tap('server-type');
      await tester.tap(find.text('UGREEN Theater').last);
      await tester.pumpAndSettle();
      expect(key('server-auth-method'), findsNothing);
      expect(key('server-api-key'), findsNothing);
      await enter('server-name', 'NAS');
      await enter('server-url', 'nas.local');
      await enter('server-username', 'alice');
      final fingerprint = List.filled(32, 'AB').join(':');
      final canonical = List.filled(32, 'ab').join();
      await enter('ugreen-fingerprint', 'invalid');
      await tap('server-test');
      expect(auth.logins, isEmpty);
      await enter('ugreen-fingerprint', fingerprint);
      await tap('server-test');
      expect(repo.items, isEmpty);
      expect(auth.logins, [('https://nas.local:9443', 'alice', '', canonical)]);
      expect(factory.validations, 1);
      await tap('server-save');
      expect(auth.logins, hasLength(1));
      final profile = repo.items.single;
      expect(profile.type, MediaServerType.ugreen);
      expect(profile.baseUrl, 'https://nas.local:9443');
      expect(profile.certificateFingerprint, canonical);
      expect(profile.accessToken, 'token-1');
      expect(profile.userId, 'user-1');
      expect(profile.toJson().containsKey('password'), isFalse);
      expect(
        ServerProfile.fromJson(profile.toJson()).certificateFingerprint,
        canonical,
      );
      expect(find.text('UGREEN Theater · alice'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      await tap('ugreen-relogin');
      expect(auth.logins, hasLength(2));
      expect(auth.logins.last.$3, '');
      final updatedPin = List.filled(64, 'c').join();
      await enter('ugreen-fingerprint', updatedPin);
      await tap('server-save');
      expect(auth.logins, hasLength(3));
      expect(auth.logins.last.$4, updatedPin);
      expect(repo.items.single.accessToken, 'token-3');
      expect(repo.items.single.certificateFingerprint, updatedPin);
    },
  );
}
