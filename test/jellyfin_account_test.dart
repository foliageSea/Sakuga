import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';

class _Adapter implements HttpClientAdapter {
  Object body = {'Id': 'alice-id', 'Name': 'Alice'};
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    final hasBody =
        options.method == 'GET' || options.path.endsWith('/PlaybackInfo');
    return ResponseBody.fromString(
      hasBody ? jsonEncode(body) : '',
      hasBody ? 200 : 204,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const account = ServerProfile(
  id: 'jellyfin',
  name: 'Jellyfin',
  baseUrl: 'https://media.test/proxy/jellyfin',
  accessToken: 'account-token',
  userId: 'alice-id',
  username: 'Alice',
  deviceId: 'device',
  remoteServerId: 'server',
);
void main() {
  late _Adapter adapter;
  late JellyfinClient client;
  setUp(() {
    adapter = _Adapter();
    final dio = Dio(
      BaseOptions(
        headers: {
          'Authorization': 'old-admin-key',
          'X-Emby-Token': 'stale-token',
        },
      ),
    )..httpClientAdapter = adapter;
    addTearDown(dio.close);
    client = JellyfinClient(server: account, dio: dio);
  });
  test(
    'account requests only logged-in user and replaces stale authentication',
    () async {
      expect(client.isConfigured, isTrue);
      expect((await client.users()).single.id, 'alice-id');
      final request = adapter.requests.single;
      expect(
        request.uri.toString(),
        'https://media.test/proxy/jellyfin/Users/alice-id',
      );
      expect(
        request.headers['Authorization'],
        contains('Token="account-token"'),
      );
      expect(
        request.headers['Authorization'],
        contains('DeviceId="device:alice"'),
      );
      expect(request.headers.values.join(), isNot(contains('old-admin-key')));
      expect(request.headers.containsKey('X-Emby-Token'), isFalse);
      expect(request.followRedirects, isFalse);
    },
  );
  test('expired account cannot silently fall back to an API key', () async {
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final expired = JellyfinClient(
      server: account.copyWith(accessToken: '', apiKey: 'admin-key'),
      dio: dio,
    );
    expect(expired.isConfigured, isFalse);
    await expectLater(
      expired.users(),
      throwsA(
        isA<AppException>().having((e) => e.kind, 'kind', FailureKind.auth),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
  test('legacy API key keeps user list and old device identity', () async {
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final legacy = JellyfinClient(
      server: const ServerProfile(
        id: 'old',
        name: 'Old',
        baseUrl: 'https://legacy.test',
        apiKey: 'legacy-key',
      ),
      dio: dio,
    );
    adapter.body = [
      {'Id': 'first-user', 'Name': 'First'},
    ];
    expect((await legacy.users()).single.id, 'first-user');
    expect(adapter.requests.single.uri.toString(), 'https://legacy.test/Users');
    expect(
      adapter.requests.single.headers['Authorization'],
      contains('Token="legacy-key"'),
    );
    expect(
      adapter.requests.single.headers['Authorization'],
      contains('DeviceId="sakuga"'),
    );
  });
  test('account token authenticates artwork playback and progress', () async {
    adapter.body = {
      'Items': [
        {
          'Id': 'movie',
          'Name': 'Movie',
          'Type': 'Movie',
          'ImageTags': {'Primary': 'tag'},
        },
      ],
      'TotalRecordCount': 1,
    };
    final page = await client.items('alice-id', 'library');
    expect(
      page.items.single.poster!.headers['Authorization'],
      contains('Token="account-token"'),
    );
    adapter.body = {
      'PlaySessionId': 'session',
      'MediaSources': [
        {'Id': 'source', 'SupportsDirectPlay': true},
      ],
    };
    final source = await client.playbackSource(
      'alice-id',
      'movie',
      startPosition: const Duration(seconds: 30),
    );
    expect(source.headers['Authorization'], contains('Token="account-token"'));
    expect(source.startPosition.inSeconds, 30);
    await client.reportPlaybackProgress(
      source.session,
      position: const Duration(seconds: 120),
      isPaused: true,
      volume: 0,
    );
    expect(adapter.requests.last.path, '/Sessions/Playing/Progress');
    expect((adapter.requests.last.data as Map)['PositionTicks'], 1200000000);
    expect(
      adapter.requests.last.headers['Authorization'],
      contains('Token="account-token"'),
    );
  });
  test('Jellyfin account survives preferences reopen and deletion', () async {
    final original = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = original);
    final repository = PreferencesServerRepository(SharedPreferencesAsync());
    await repository.save([account.copyWith(apiKey: 'obsolete-key')]);
    final reopened = PreferencesServerRepository(SharedPreferencesAsync());
    final restored = (await reopened.load()).single;
    expect(restored.usesAccount, isTrue);
    expect(restored.accessToken, 'account-token');
    expect(restored.apiKey, isEmpty);
    expect(restored.userId, 'alice-id');
    expect(restored.deviceId, 'device');
    await reopened.save([]);
    expect(await repository.load(), isEmpty);
  });
}
