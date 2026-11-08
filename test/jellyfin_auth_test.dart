import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/jellyfin/jellyfin_auth.dart';
import 'package:sakuga/data/jellyfin/jellyfin_protocol.dart';

class _Adapter implements HttpClientAdapter {
  Object body = {
    'AccessToken': 'account-token',
    'User': {'Id': 'alice-id', 'Name': 'Alice'},
    'ServerId': 'jellyfin-server',
  };
  int status = 200;
  DioExceptionType? failure;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    request = options;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late JellyfinAuthService auth;
  setUp(() {
    adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    auth = JellyfinAuthService(dio: dio);
  });
  Future<JellyfinAuthResult> login({
    String baseUrl = 'https://media.test/proxy/jellyfin/',
    String username = ' Alice ',
    String password = ' password ',
  }) => auth.authenticate(
    baseUrl: baseUrl,
    username: username,
    password: password,
    deviceId: 'device',
  );

  test('Jellyfin login preserves proxy path and password with MediaBrowser identity', () async {
    final result = await login();
    expect(result.accessToken, 'account-token');
    expect(result.userId, 'alice-id');
    expect(result.username, 'Alice');
    expect(result.remoteServerId, 'jellyfin-server');
    final request = adapter.request!;
    expect(
      request.uri.toString(),
      'https://media.test/proxy/jellyfin/Users/AuthenticateByName',
    );
    expect(request.data, {'Username': 'Alice', 'Pw': ' password '});
    expect(
      request.headers['Authorization'],
      contains('MediaBrowser Client="Sakuga"'),
    );
    expect(
      request.headers['Authorization'],
      contains('DeviceId="device:alice"'),
    );
    expect(request.headers['Authorization'], isNot(contains('Token=')));
    expect(
      request.headers.keys.any((key) => key.toLowerCase().startsWith('x-emby')),
      isFalse,
    );
    expect(request.followRedirects, isFalse);
  });
  test(
    'root URL does not acquire an Emby prefix and empty passwords work',
    () async {
      await login(baseUrl: 'https://media.test/', password: '');
      expect(adapter.request!.uri.path, '/Users/AuthenticateByName');
      expect((adapter.request!.data as Map)['Pw'], '');
    },
  );
  test('device identities separate users but ignore username case and surrounding spaces', () {
    expect(
      jellyfinDeviceIdentity('device', 'Alice'),
      jellyfinDeviceIdentity('device', ' ALICE '),
    );
    expect(
      jellyfinDeviceIdentity('device', 'alice'),
      isNot(jellyfinDeviceIdentity('device', 'bob')),
    );
    expect(
      jellyfinAuthHeaders(
        username: 'A"B\n',
        deviceId: 'device',
      )['Authorization'],
      isNot(contains('\n')),
    );
  });
  test('empty username does not send credentials', () async {
    await expectLater(
      login(username: ' '),
      throwsA(
        isA<AppException>().having(
          (e) => e.kind,
          'kind',
          FailureKind.invalidData,
        ),
      ),
    );
    expect(adapter.request, isNull);
  });
  for (final body in [
    <String, dynamic>{
      'User': {'Id': 'alice'},
    },
    <String, dynamic>{'AccessToken': 'token', 'User': {}},
    <String, dynamic>{
      'AccessToken': '',
      'User': {'Id': 'alice'},
    },
  ]) {
    test(
      'malformed authentication result cannot create a session: ${body.keys}',
      () async {
        adapter.body = body;
        await expectLater(
          login(),
          throwsA(
            isA<AppException>()
                .having((e) => e.kind, 'kind', FailureKind.invalidData)
                .having((e) => e.cause, 'cause', isNull),
          ),
        );
      },
    );
  }
  for (final status in [401, 403, 500]) {
    test('HTTP $status is sanitized and categorized', () async {
      adapter.status = status;
      await expectLater(
        login(),
        throwsA(
          isA<AppException>()
              .having(
                (e) => e.kind,
                'kind',
                status == 401 ? FailureKind.auth : FailureKind.server,
              )
              .having((e) => e.cause, 'cause', status == 403 ? 403 : isNull),
        ),
      );
    });
  }
  test('timeout does not retain credential-bearing request', () async {
    adapter.failure = DioExceptionType.receiveTimeout;
    await expectLater(
      login(),
      throwsA(
        isA<AppException>()
            .having((e) => e.kind, 'kind', FailureKind.timeout)
            .having((e) => e.cause, 'cause', isNull),
      ),
    );
  });
}
