import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/emby/emby_auth.dart';

class _Adapter implements HttpClientAdapter {
  Object body = {
    'AccessToken': 'secret',
    'User': {'Id': 'user', 'Name': 'Alice'},
    'ServerId': 'remote',
  };
  int status = 200;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    request = options;
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
  late EmbyAuthService auth;
  setUp(() {
    adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    auth = EmbyAuthService(dio: dio);
  });
  Future<EmbyAuthResult> login({String password = ' password '}) =>
      auth.authenticate(
        baseUrl: 'https://media.test/proxy/emby/',
        username: ' Alice ',
        password: password,
        deviceId: 'device',
      );
  test(
    'login preserves password and uses client identity at proxy API root',
    () async {
      final result = await login();
      expect(result.accessToken, 'secret');
      expect(result.userId, 'user');
      expect(result.remoteServerId, 'remote');
      final request = adapter.request!;
      expect(
        request.uri.toString(),
        'https://media.test/proxy/emby/Users/AuthenticateByName',
      );
      expect(request.data, {'Username': 'Alice', 'Pw': ' password '});
      expect(
        request.headers['X-Emby-Authorization'],
        contains('DeviceId="device"'),
      );
      expect(request.headers.containsKey('X-Emby-Token'), isFalse);
      expect(request.followRedirects, isFalse);
    },
  );
  test('accounts with empty passwords still authenticate', () async {
    await login(password: '');
    expect((adapter.request!.data as Map)['Pw'], '');
  });
  test(
    'rejects malformed successful responses without retaining secrets',
    () async {
      adapter.body = {'AccessToken': 'secret', 'User': {}};
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
  for (final status in [401, 403]) {
    test(
      'maps $status without retaining credential-bearing requests',
      () async {
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
                .having((e) => e.cause, 'cause', status == 401 ? isNull : 403),
          ),
        );
      },
    );
  }
}
