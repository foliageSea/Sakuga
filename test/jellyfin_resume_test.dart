import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/media_server/server_profile.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int statusCode = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'Items': [
          for (final id in ['episode-4', 'episode-5', 'movie'])
            {
              'Id': id,
              'Name': id,
              'Type': id == 'movie' ? 'Movie' : 'Episode',
              'SeriesId': id == 'movie' ? null : 'series',
              'SeasonId': id == 'movie' ? null : 'season',
              'ParentIndexNumber': 1,
            },
        ],
      }),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

JellyfinClient _client(_Adapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://media.test'))
    ..httpClientAdapter = adapter;
  addTearDown(dio.close);
  return JellyfinClient(
    server: const ServerProfile(
      id: 'server',
      name: 'Server',
      baseUrl: 'https://media.test',
      apiKey: 'key',
    ),
    dio: dio,
  );
}

void main() {
  test(
    'uses native resume endpoint without overriding server grouping or sorting',
    () async {
      final adapter = _Adapter();
      final items = await _client(adapter).resume('user', limit: 20);
      expect(items.map((item) => item.id), ['episode-4', 'episode-5', 'movie']);
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.path, '/Users/user/Items/Resume');
      expect(request.queryParameters['limit'], 20);
      expect(
        request.queryParameters['fields'].toString(),
        contains('UserData'),
      );
      expect(request.queryParameters.containsKey('filters'), isFalse);
      expect(request.queryParameters.containsKey('sortBy'), isFalse);
      expect(request.queryParameters.containsKey('sortOrder'), isFalse);
    },
  );

  test('marks played using the Jellyfin played-items endpoint', () async {
    final adapter = _Adapter();
    await _client(adapter).setPlayed('user', 'episode-4', played: true);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/user/PlayedItems/episode-4');
    expect(request.data, isNull);
  });

  test(
    'marks unplayed using DELETE rather than inventing playback progress',
    () async {
      final adapter = _Adapter();
      await _client(adapter).setPlayed('other-user', 'movie', played: false);
      final request = adapter.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/Users/other-user/PlayedItems/movie');
      expect(request.data, isNull);
    },
  );

  test('played-state API propagates server failures', () async {
    final adapter = _Adapter()..statusCode = 403;
    await expectLater(
      _client(adapter).setPlayed('user', 'episode-4', played: true),
      throwsA(isA<DioException>()),
    );
  });
}
