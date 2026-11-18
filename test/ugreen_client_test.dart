import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/playback_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/ugreen/ugreen_auth.dart';
import 'package:sakuga/data/ugreen/ugreen_client.dart';
import 'package:sakuga/data/ugreen/ugreen_transport.dart';

const _server = ServerProfile(
  id: 'nas-profile',
  name: 'NAS',
  baseUrl: 'nas.test',
  type: MediaServerType.ugreen,
  userId: '24',
  username: 'media-user',
  accessToken: 'tok+en',
  deviceId: 'my-device',
);

final _invalidData = isA<AppException>().having(
  (e) => e.kind,
  'kind',
  FailureKind.invalidData,
);
final _auth = isA<AppException>().having(
  (e) => e.kind,
  'kind',
  FailureKind.auth,
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond, {this.status = 200});

  final Object Function(RequestOptions) respond;
  final int status;
  final requests = <RequestOptions>[];

  Dio get dio {
    final dio = Dio()..httpClientAdapter = this;
    addTearDown(dio.close);
    return dio;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(respond(options)),
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
  test(
    'auth uses the public 9443 route with an empty password and no token',
    () async {
      final adapter = _Adapter(
        (_) => {
          'AccessToken': 'token',
          'User': {'Id': 24, 'Name': 'NAS user'},
          'UserId': 25,
          'ServerId': 'nas',
        },
      );
      final result = await UgreenAuthService(dio: adapter.dio).authenticate(
        baseUrl: 'nas.test',
        username: ' alice ',
        password: '',
        deviceId: 'dev',
      );
      final request = adapter.requests.single;
      expect(
        request.uri.toString(),
        'https://nas.test:9443/emby/Users/AuthenticateByName',
      );
      expect(request.method, 'POST');
      expect(request.followRedirects, isFalse);
      expect(request.data, {'Username': 'alice', 'Pw': ''});
      expect(
        request.headers['X-Emby-Authorization'],
        startsWith('MediaBrowser '),
      );
      expect(
        request.headers['X-Emby-Authorization'],
        contains('DeviceId="dev"'),
      );
      expect(
        request.headers['X-Emby-Authorization'],
        isNot(contains('Token=')),
      );
      expect(result.accessToken, 'token');
      expect(result.userId, '24');
      expect(result.username, 'NAS user');
      expect(result.remoteServerId, 'nas');
    },
  );

  test(
    'auth falls back to UserId, rejects blanks and redacts HTTP errors',
    () async {
      Future<void> authenticateWith(_Adapter adapter) async {
        final result = await UgreenAuthService(dio: adapter.dio).authenticate(
          baseUrl: 'https://nas.test:10443',
          username: 'alice',
          password: 'secret',
          deviceId: 'dev',
        );
        expect(result.userId, '24');
        expect(result.username, 'alice');
      }

      final fallback = _Adapter(
        (_) => {'AccessToken': 'token', 'UserId': '24'},
      );
      await authenticateWith(fallback);
      expect(fallback.requests.single.uri.port, 10443);
      await expectLater(
        authenticateWith(_Adapter((_) => {'AccessToken': '', 'UserId': 24})),
        throwsA(_invalidData),
      );
      await expectLater(
        authenticateWith(
          _Adapter((_) => {'secret': 'session token'}, status: 403),
        ),
        throwsA(_auth.having((e) => e.cause, 'safe status', 403)),
      );
    },
  );

  test(
    'validates the account using Views and maps an offset library page',
    () async {
      final adapter = _Adapter(
        (request) => switch (request.uri.path) {
          '/emby/Users/24/Views' => {
            'Items': [
              {'Id': 9, 'Name': 'TV', 'CollectionType': 'tvshows'},
            ],
          },
          '/emby/Users/24/Items' => {
            'TotalRecordCount': 6,
            'Items': [
              {
                'Id': 42,
                'Name': 'Test',
                'Type': 'Series',
                'ImageTags': {'Primary': 'poster'},
              },
              {'Name': 'Ignored'},
            ],
          },
          _ => throw StateError('unexpected route'),
        },
      );
      final client = UgreenClient(server: _server, dio: adapter.dio);
      final user = (await client.users()).single;
      expect(user.id, '24');
      expect(user.name, 'media-user');
      expect((await client.views('24')).single.type, MediaLibraryType.tvShows);
      await expectLater(client.views('other'), throwsA(_auth));
      final page = await client.items(
        '24',
        '9',
        startIndex: 2,
        limit: 2,
        types: {MediaType.series},
      );
      expect(page.totalRecordCount, 6);
      expect(page.hasMore, isTrue);
      expect(page.nextStartIndex, 4);
      final poster = page.items.single.poster!;
      expect(page.items.single.id, '42');
      expect(
        poster.url(),
        startsWith('https://nas.test:9443/emby/Items/42/Images/Primary?'),
      );
      expect(poster.url(), isNot(contains('api_key')));
      expect(poster.headers[ugreenArtworkProfileHeader], 'nas-profile');
      expect(poster.headers[ugreenArtworkTokenHeader], 'tok+en');
      final [view, items] = adapter.requests;
      expect(view.uri.path, '/emby/Users/24/Views');
      expect(items.uri.queryParameters, containsPair('ParentId', '9'));
      expect(items.uri.queryParameters, containsPair('StartIndex', '2'));
      expect(items.uri.queryParameters, containsPair('Limit', '2'));
      expect(
        items.uri.queryParameters,
        containsPair('IncludeItemTypes', 'Series'),
      );
      for (final request in adapter.requests) {
        expect(request.method, 'GET');
        expect(request.uri.origin, 'https://nas.test:9443');
        expect(request.uri.queryParameters['api_key'], 'tok+en');
        expect(
          request.headers['X-Emby-Authorization'],
          contains('Token="tok+en"'),
        );
        expect(request.followRedirects, isFalse);
      }
    },
  );

  test(
    'does not treat a malformed view envelope as a validated account',
    () async {
      final client = UgreenClient(
        server: _server,
        dio: _Adapter((_) => {}).dio,
      );
      await expectLater(client.users(), throwsA(_invalidData));
    },
  );

  test('details use the single-item route, search uses SearchTerm, and resume is a read', () async {
    final adapter = _Adapter((request) {
      final row = {
        'Id': 42,
        'Type': request.uri.path.endsWith('/42') ? 'Series' : 'Movie',
        'UserData': {'PlaybackPositionTicks': 20000000},
      };
      return request.uri.path.endsWith('/42')
          ? row
          : {
              'Items': [row],
            };
    });
    final client = UgreenClient(server: _server, dio: adapter.dio);
    expect((await client.item('24', '42')).type, MediaType.series);
    expect((await client.search('24', ' a & b ')).single.id, '42');
    expect(
      (await client.resume('24')).single.playbackPosition,
      const Duration(seconds: 2),
    );
    expect((await client.latest('24', limit: 1)).single.id, '42');
    expect(await client.randomItems('24'), isEmpty);
    expect(await client.genres('24', '9'), isEmpty);
    expect(await client.years('24', '9'), isEmpty);
    final [details, search, resume, latest] = adapter.requests;
    expect(latest.uri.path, search.uri.path);
    expect(latest.uri.queryParameters, containsPair('SortBy', 'DateCreated'));
    expect(latest.uri.queryParameters, containsPair('SortOrder', 'Descending'));
    expect(
      latest.uri.queryParameters,
      containsPair('IncludeItemTypes', 'Movie,Series'),
    );
    expect(latest.uri.queryParameters, containsPair('Limit', '1'));
    expect(details.uri.path, '/emby/Users/24/Items/42');
    expect(details.uri.queryParameters, isNot(contains('Ids')));
    expect(search.uri.path, '/emby/Users/24/Items');
    expect(search.uri.queryParameters, containsPair('SearchTerm', 'a & b'));
    expect(resume.uri.path, '/emby/Users/24/Items/Resume');
    expect(resume.method, 'GET');
  });

  test(
    'synthesizes season details and loads episodes with numeric Season',
    () async {
      final adapter = _Adapter(
        (_) => {
          'Items': [
            {'Id': 53, 'ParentIndexNumber': 2, 'IndexNumber': 2},
            {'Id': 31, 'ParentIndexNumber': 0, 'IndexNumber': 1},
            {'Id': 52, 'ParentIndexNumber': 2, 'IndexNumber': 1},
          ],
        },
      );
      final client = UgreenClient(server: _server, dio: adapter.dio);
      final seasons = await client.seasons('24', '44');
      expect(seasons.map((season) => season.indexNumber), [0, 2]);
      final seasonId = seasons.last.id;
      final detail = await client.item('24', seasonId);
      expect(detail.childCount, 2);
      expect(detail.seriesId, '44');
      final episodes = await client.episodes('24', '44', seasonId: seasonId);
      expect(episodes.map((item) => item.id), ['52', '53']);
      expect(episodes.first.seasonId, seasonId);
      await expectLater(
        client.episodes('24', '99', seasonId: seasonId),
        throwsA(_invalidData),
      );
      expect(adapter.requests, hasLength(1));
      final freshClient = UgreenClient(server: _server, dio: adapter.dio);
      await freshClient.episodes('24', '44', seasonId: seasonId);
      final [group, filtered] = adapter.requests;
      expect(group.uri.path, '/emby/Shows/44/Episodes');
      expect(group.uri.queryParameters, isNot(contains('Season')));
      expect(filtered.uri.path, '/emby/Shows/44/Episodes');
      expect(filtered.uri.queryParameters, containsPair('Season', '2'));
      expect(filtered.uri.queryParameters, containsPair('IsMissing', 'false'));
    },
  );

  test('playback rejects foreign, Path and transcoding sources', () async {
    final adapter = _Adapter(
      (_) => {
        'MediaSources': [
          {'DirectStreamUrl': 'https://other.test:9443/video.mp4'},
          {'DirectStreamUrl': '//nas.test:9444/video.mp4'},
          {'DirectStreamUrl': 'http://nas.test:9443/video.mp4'},
          {'DirectStreamUrl': '/emby/video.m3u8'},
          {'DirectStreamUrl': 'https://user@nas.test:9443/video.mp4'},
          {
            'Path': 'https://nas.test:9443/video.mp4',
            'TranscodingUrl': '/video.m3u8',
          },
        ],
      },
    );
    final client = UgreenClient(server: _server, dio: adapter.dio);
    await expectLater(client.playbackSource('24', '42'), throwsA(_invalidData));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/emby/Items/42/PlaybackInfo');
    expect(request.data, containsPair('IsPlayback', false));
    expect(request.data, containsPair('EnableTranscoding', false));
    expect(request.data, containsPair('UserId', '24'));
  });

  test('playback exposes only a local capability and cleans it without remote writes', () async {
    final adapter = _Adapter(
      (_) => {
        'MediaSources': [
          {'DirectStreamUrl': '/emby/Videos/42/stream?static=true&key=1&key=2'},
        ],
      },
    );
    final client = UgreenClient(server: _server, dio: adapter.dio);
    const position = Duration(minutes: 2);
    final source = await client.playbackSource(
      '24',
      '42',
      startPosition: position,
    );
    addTearDown(() => client.stopTranscoding(source.session));
    final url = Uri.parse(source.url);
    expect(url.scheme, 'http');
    expect(url.host, InternetAddress.loopbackIPv4.address);
    expect(url.hasQuery, isFalse);
    expect(source.headers, isEmpty);
    expect(source.playMethod, PlayMethod.directPlay);
    expect(source.startPosition, position);
    await client.reportPlaybackStarted(
      source.session,
      position: position,
      isPaused: false,
    );
    await client.reportPlaybackProgress(
      source.session,
      position: position,
      isPaused: false,
    );
    await client.reportPlaybackStopped(
      source.session,
      position: position,
      failed: false,
    );
    await client.updatePlaybackPosition('24', '42', position: position);
    await expectLater(
      client.setPlayed('24', '42', played: true),
      throwsUnsupportedError,
    );
    await client.stopTranscoding(source.session);
    final local = HttpClient();
    addTearDown(() => local.close(force: true));
    await expectLater(local.getUrl(url), throwsA(isA<SocketException>()));
    expect(adapter.requests, hasLength(1));
  });
}
