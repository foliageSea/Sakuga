import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sakuga/data/fnmovie/fnmovie_auth.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';
import 'package:sakuga/features/settings/servers_section.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

class _Auth extends Fake implements FnMovieAuthService {
  final logins = <(String, String, String)>[];

  @override
  Future<FnMovieAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    logins.add((baseUrl, username, password));
    return (
      accessToken: 'token-${logins.length}',
      baseUrl: 'http://nas.local:8000/v',
    );
  }
}

void main() {
  testWidgets(
    'fnOS Media tests without saving and re-login preserves identity',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _Auth();
      final repo = MemoryServerRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverRepositoryProvider.overrideWithValue(repo),
            fnMovieAuthProvider.overrideWithValue(auth),
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
      await tester.tap(find.text('fnOS Media').last);
      await tester.pumpAndSettle();
      expect(key('server-auth-method'), findsNothing);
      expect(key('server-api-key'), findsNothing);
      await enter('server-name', 'NAS');
      await enter('server-url', 'nas.local');
      await enter('server-username', 'alice');
      await enter('server-password', 'nas-secret');
      await tap('server-test');
      expect(repo.items, isEmpty);
      expect(auth.logins, [('http://nas.local', 'alice', 'nas-secret')]);
      await tap('server-save');
      expect(auth.logins, hasLength(1));
      final profile = repo.items.single;
      expect(profile.type, MediaServerType.fnmovie);
      expect(profile.baseUrl, 'http://nas.local:8000/v');
      expect(profile.accessToken, 'token-1');
      expect(profile.userId, profile.id);
      expect(profile.toJson().values, isNot(contains('nas-secret')));
      expect(find.text('fnOS Media · alice'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      await enter('server-password', 'new-secret');
      await tap('server-save');
      expect(auth.logins.last, (profile.baseUrl, 'alice', 'new-secret'));
      expect(repo.items.single.id, profile.id);
      expect(repo.items.single.userId, profile.userId);
      expect(repo.items.single.accessToken, 'token-2');
    },
  );
}
