import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';

class _Preferences extends SharedPreferencesAsync {
  _Preferences(this.shouldFailWrite);
  final bool Function() shouldFailWrite;
  @override
  Future<void> setString(String key, String value) {
    if (shouldFailWrite()) throw StateError('storage unavailable');
    return super.setString(key, value);
  }
}

const _server = ServerProfile(
  id: 'profile',
  name: 'Emby',
  baseUrl: 'https://media.test',
  type: MediaServerType.emby,
  userId: 'alice',
  username: 'Alice',
  deviceId: 'device',
  remoteServerId: 'remote',
  accessToken: 'token-one',
);

void main() {
  late _Preferences preferences;
  late bool failWrite;
  late PreferencesServerRepository repository;
  setUp(() {
    final original = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
    failWrite = false;
    preferences = _Preferences(() => failWrite);
    repository = PreferencesServerRepository(preferences);
  });

  test(
    'preferences restore Emby and Jellyfin sessions after repository reopen',
    () async {
      const jellyfin = ServerProfile(
        id: 'jellyfin',
        name: 'Jellyfin',
        baseUrl: 'https://jellyfin.test',
        apiKey: 'jellyfin-key',
      );
      await repository.save([_server, jellyfin]);
      final json = jsonDecode(
        (await preferences.getString(PreferencesServerRepository.key))!,
      ) as List;
      expect((json.first as Map)['accessToken'], 'token-one');
      expect((json.first as Map).containsKey('credentialId'), isFalse);
      expect((json.first as Map).containsKey('password'), isFalse);
      final reopened = PreferencesServerRepository(SharedPreferencesAsync());
      final profiles = await reopened.load();
      expect(profiles.first.accessToken, 'token-one');
      expect(profiles.first.userId, 'alice');
      expect(profiles.last.apiKey, 'jellyfin-key');
      await reopened.save([
        profiles.first.copyWith(name: 'Renamed'),
        profiles.last,
      ]);
      expect((await reopened.load()).first.accessToken, 'token-one');
      expect((await reopened.load()).first.name, 'Renamed');
    },
  );

  test(
    'rotation replaces the token and deletion removes it from preferences',
    () async {
      await repository.save([_server]);
      await repository.save([_server.copyWith(accessToken: 'token-two')]);
      expect((await repository.load()).single.accessToken, 'token-two');
      expect(
        await preferences.getString(PreferencesServerRepository.key),
        isNot(contains('token-one')),
      );
      await repository.save([]);
      expect(await repository.load(), isEmpty);
      expect(
        await preferences.getString(PreferencesServerRepository.key),
        isNot(contains('token-two')),
      );
    },
  );

  test('failed preferences write leaves the saved session usable', () async {
    await repository.save([_server]);
    failWrite = true;
    await expectLater(
      repository.save([_server.copyWith(accessToken: 'token-two')]),
      throwsA(
        isA<AppException>().having((e) => e.kind, 'kind', FailureKind.storage),
      ),
    );
    expect((await repository.load()).single.accessToken, 'token-one');
  });

  test(
    'legacy secure-store profiles retain metadata and require login',
    () async {
      await preferences.setString(
        PreferencesServerRepository.key,
        jsonEncode([
          {
            'id': 'legacy',
            'name': 'Emby',
            'baseUrl': 'https://media.test',
            'type': 'emby',
            'userId': 'alice',
            'username': 'Alice',
            'deviceId': 'device',
            'credentialId': 'old-reference',
          },
        ]),
      );
      final profile = (await repository.load()).single;
      expect(profile.accessToken, isEmpty);
      expect(profile.username, 'Alice');
      expect(profile.userId, 'alice');
      await repository.save([profile.copyWith(accessToken: 'new-login-token')]);
      expect((await repository.load()).single.accessToken, 'new-login-token');
      expect(
        await preferences.getString(PreferencesServerRepository.key),
        isNot(contains('credentialId')),
      );
    },
  );
}
