import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/images/artwork_cache.dart';
import 'package:sakuga/data/fnmovie/fnmovie_auth.dart';
import 'package:sakuga/data/fnmovie/fnmovie_client.dart';
import 'package:sakuga/data/fnmovie/fnmovie_protocol.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/media_server_factory.dart';
import 'package:sakuga/data/media_server/server_profile.dart';

const _token = 'mock-session';
const _user = 'profile';

typedef _Handler = Future<void> Function(HttpRequest request, String body);

Future<String> _serve(_Handler handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    try {
      await handler(request, await utf8.decoder.bind(request).join());
    } catch (error) {
      request.response.statusCode = 500;
      request.response.write('$error');
    } finally {
      await request.response.close();
    }
  });
  return 'http://127.0.0.1:${server.port}';
}

void _json(HttpRequest request, Object? data, {int code = 0}) {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode({'code': code, 'data': data}));
}

void _checkSignature(
  HttpRequest request,
  String body, {
  String? token = _token,
}) {
  expect(request.headers.value('authorization'), token);
  final header = request.headers.value('authx');
  expect(header, isNotNull);
  final parts = Uri.splitQueryString(header!);
  expect(
    header,
    fnMovieSignature(
      request.requestedUri,
      request.method,
      body: body,
      nonce: int.parse(parts['nonce']!),
      timestamp: int.parse(parts['timestamp']!),
    ),
  );
  expect(request.headers.value('X-Trim-Client'), 'web');
  expect(request.headers.value(fnMovieArtworkOriginHeader), isNull);
  expect(request.headers.value(fnMovieArtworkProfileHeader), isNull);
}

ServerProfile _profile(String base) => ServerProfile(
  id: _user,
  name: 'NAS',
  baseUrl: base,
  type: MediaServerType.fnmovie,
  accessToken: _token,
  userId: _user,
  username: 'alice',
);

void main() {
  const nativeFixture = String.fromEnvironment('FNMOVIE_NATIVE_FIXTURE');

  test(
    'libmpv opens and seeks through the signed fnOS Media Range proxy',
    () async {
      MediaKit.ensureInitialized();
      final file = File(nativeFixture);
      final length = await file.length();
      final offsets = <int>[];
      final base = await _serve((request, body) async {
        _checkSignature(request, body);
        switch (request.uri.path) {
          case '/api/v1/play/info':
            _json(request, {'media_guid': 'media', 'ts': 20, 'duration': 596});
          case '/api/v1/stream':
            _json(request, {
              'video_stream': {'duration': 596},
            });
          case '/api/v1/media/range/media':
            final raw = request.headers.value('range');
            final range = raw == null
                ? null
                : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(raw);
            final start = range == null ? 0 : int.parse(range[1]!);
            final end = range == null || range[2]!.isEmpty
                ? length - 1
                : int.parse(range[2]!);
            offsets.add(start);
            request.response.headers.contentType = ContentType('video', 'mp4');
            request.response.headers.set('accept-ranges', 'bytes');
            request.response.contentLength = end - start + 1;
            if (range != null) {
              request.response.statusCode = 206;
              request.response.headers.set(
                'content-range',
                'bytes $start-$end/$length',
              );
            }
            if (request.method != 'HEAD') {
              try {
                await request.response.addStream(file.openRead(start, end + 1));
              } on HttpException {
                // mpv may abandon a range in favor of a seek.
              }
            }
          default:
            fail('Unexpected endpoint: ${request.uri.path}');
        }
      });
      final client = FnMovieClient(server: _profile(base));
      final source = await client.playbackSource(_user, 'movie');
      final player = Player(
        configuration: const PlayerConfiguration(
          vo: 'null',
          logLevel: MPVLogLevel.debug,
        ),
      );
      final errors = <String>[];
      final subscription = player.stream.error.listen(errors.add);
      final logs = <String>[];
      final logSubscription = player.stream.log.listen((entry) {
        logs.add('${entry.prefix}: ${entry.text}');
        if (logs.length > 80) logs.removeAt(0);
      });
      try {
        final native = player.platform! as NativePlayer;
        await native.setProperty('vid', 'auto');
        await native.setProperty('audio', 'no');
        await native.setProperty('cache', 'no');
        Future<Duration> waitForPosition(int seconds) async {
          // Use player state as well as event delivery: paused seeks may not
          // notify until playback resumes with the null video output.
          final timeout = Stopwatch()..start();
          while (timeout.elapsed < const Duration(seconds: 12)) {
            final position = player.state.position;
            if (position.inSeconds >= seconds) return position;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          throw TestFailure(
            'Position did not reach ${seconds}s; '
            'position=${player.state.position}, duration=${player.state.duration}, '
            'offsets=$offsets, errors=$errors\n${logs.join('\n')}',
          );
        }

        await player.open(Media(source.url, start: source.startPosition));
        expect(
          await waitForPosition(20),
          lessThan(const Duration(seconds: 40)),
        );
        await player.pause();
        await player.seek(const Duration(seconds: 120));
        await player.play();
        expect(
          await waitForPosition(119),
          lessThan(const Duration(seconds: 125)),
        );
        expect(offsets.any((offset) => offset > 0), isTrue);
      } finally {
        await subscription.cancel();
        await logSubscription.cancel();
        await player.dispose();
        await client.stopTranscoding(source.session);
      }
    },
    skip: nativeFixture.isEmpty
        ? 'Set FNMOVIE_NATIVE_FIXTURE to the local Big Buck Bunny MP4'
        : false,
  );

  test('request signing preserves UTF-8, repeated keys, and escaped paths', () {
    String sign(String path, String method, [String body = '']) =>
        fnMovieSignature(
          Uri.parse('http://nas.example/proxy/api/v1/$path'),
          method,
          body: body,
          timestamp: 1730000000000,
          nonce: 123456,
        ).split('sign=').last;
    expect(
      sign('search/list?z=%E9%A3%9E+%E7%89%9B&a=x%2By&a=one', 'GET'),
      '6f3bf980b69d9afc4c0fef639771a847',
    );
    expect(
      sign('item/list', 'POST', '{"ancestor_guid":"库","page":1}'),
      '94c6a5f79fc359c18eefabc3c0fa96bc',
    );
    expect(sign('item/ep%2F1', 'GET'), '77c9c759349dbf8a2770b4c3145574cc');
  });

  test(
    'login validates the signed library endpoint and maps expired sessions',
    () async {
      var expired = false;
      final paths = <String>[];
      final base = await _serve((request, body) async {
        final path = request.uri.path;
        paths.add(path);
        switch (path) {
          case '/proxy/api/v1/login':
            _checkSignature(request, body, token: null);
            expect(jsonDecode(body), {
              'username': 'alice',
              'password': ' 密码 ',
              'app_name': 'Sakuga',
            });
            request.response.statusCode = 307;
            request.response.headers.set('location', '/v/api/v1/login');
          case '/v/api/v1/login':
            _checkSignature(request, body, token: null);
            _json(request, {'token': _token});
          case '/v/api/v1/mdb/list':
            _checkSignature(request, body);
            _json(request, [
              {'guid': 'library', 'name': 'Movies', 'type': 'Movie'},
            ], code: expired ? 401 : 0);
          default:
            fail('Unexpected endpoint: $path');
        }
      });
      final auth = await FnMovieAuthService().authenticate(
        baseUrl: '$base/proxy',
        username: 'alice',
        password: ' 密码 ',
      );
      expect(auth, (accessToken: _token, baseUrl: '$base/v'));
      expect(paths, [
        '/proxy/api/v1/login',
        '/v/api/v1/login',
        '/v/api/v1/mdb/list',
      ]);
      final profile = ServerProfile.fromJson(_profile(auth.baseUrl).toJson());
      final client = const MediaServerFactory().createClient(profile);
      expect(client, isA<FnMovieClient>());
      expect((await client.users()).single.id, _user);
      expect((await client.views(_user)).single.type, MediaLibraryType.movies);
      expired = true;
      await expectLater(
        client.users(),
        throwsA(
          isA<AppException>().having((e) => e.kind, 'kind', FailureKind.auth),
        ),
      );
    },
  );

  test(
    'catalog keeps raw page boundaries and resolves series, cast and search',
    () async {
      final pages = <int>[];
      final base = await _serve((request, body) async {
        _checkSignature(request, body);
        switch (request.uri.path) {
          case '/p/api/v1/item/list':
            final payload = jsonDecode(body) as Map<String, dynamic>;
            expect(payload['ancestor_guid'], 'my-lib');
            expect(payload['page_size'], 60);
            expect(payload['tags'], {
              'type': ['Movie', 'TV', 'Video'],
            });
            final page = payload['page'] as int;
            pages.add(page);
            final rows = switch (page) {
              1 => [
                {
                  'guid': 'series',
                  'title': '番剧',
                  'type': 'TV',
                  'ancestor_guid': 'my-lib',
                },
                {
                  'guid': 'other',
                  'title': 'Other',
                  'type': 'Movie',
                  'ancestor_guid': 'other-lib',
                },
              ],
              2 => [
                {
                  'guid': 'folder',
                  'title': 'Folder',
                  'type': 'Directory',
                  'ancestor_guid': 'my-lib',
                },
                {
                  'guid': 'video',
                  'title': 'Video',
                  'type': 'Video',
                  'ancestor_guid': 'my-lib',
                },
              ],
              3 => [
                {
                  'guid': 'last',
                  'title': 'Last',
                  'type': 'Movie',
                  'ancestor_guid': 'my-lib',
                },
              ],
              _ => throw StateError('Unexpected page'),
            };
            _json(request, {'total': 5, 'list': rows});
          case '/p/api/v1/search/list':
            expect(request.uri.queryParameters, {'q': '番 剧 +'});
            _json(request, {
              'items': [
                {'guid': 'series', 'title': '番剧', 'type': 'TV'},
              ],
            });
          case '/p/api/v1/item/series':
            request.response.statusCode = 404;
          case '/p/api/v1/tv/series':
            _json(request, {
              'tv': {
                'title': '番剧',
                'overview': 'Overview',
                'posters': [
                  {'path': 'show/a.jpg'},
                ],
              },
            });
          case '/p/api/v1/person/list/series':
            _json(request, [
              {'guid': 'person', 'name': 'Actor', 'character': 'Role'},
            ]);
          case '/p/api/v1/season/list/series':
            _json(request, [
              {'guid': 'season', 'type': 'Season', 'season_number': 1},
            ]);
          case '/p/api/v1/episode/list/season':
            _json(request, {
              'list': [
                {
                  'guid': 'two',
                  'type': 'Video',
                  'episode_number': 2,
                  'season_number': 1,
                },
                {
                  'guid': 'one',
                  'type': 'Episode',
                  'episode_number': 1,
                  'season_number': 1,
                },
              ],
            });
          default:
            fail('Unexpected endpoint: ${request.uri.path}');
        }
      });
      final client = FnMovieClient(server: _profile('$base/p'));
      final first = await client.items(_user, 'my-lib');
      expect(first.items.single.id, 'series');
      final second = await client.items(
        _user,
        'my-lib',
        startIndex: first.nextStartIndex!,
      );
      expect(second.items.single.type, MediaType.video);
      final third = await client.items(
        _user,
        'my-lib',
        startIndex: second.nextStartIndex!,
      );
      expect(third.items.single.id, 'last');
      expect(third.hasMore, isFalse);
      expect(pages, [1, 2, 3]);
      expect((await client.search(_user, '番 剧 +')).single.id, 'series');
      final detail = await client.item(_user, 'series');
      expect(detail.people.single.role, 'Role');
      expect(detail.poster!.url(), '$base/p/api/v1/sys/img/show/a.jpg');
      final season = (await client.seasons(_user, 'series')).single;
      expect(season.indexNumber, 1);
      final episodes = await client.episodes(
        _user,
        'series',
        seasonId: season.id,
      );
      expect(
        episodes.map(
          (item) => (item.id, item.seriesId, item.seasonId, item.episodeCode),
        ),
        [
          ('one', 'series', 'season', 'S01E01'),
          ('two', 'series', 'season', 'S01E02'),
        ],
      );
    },
  );

  test('artwork signs at download time and refuses cross-origin credential redirects', () async {
    var externalRequests = 0;
    final external = await _serve((request, body) async {
      externalRequests++;
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('authx'), isNull);
      expect(request.headers.value(fnMovieArtworkProfileHeader), isNull);
      request.response.write('image');
    });
    final base = await _serve((request, body) async {
      _checkSignature(request, body);
      switch (request.uri.path) {
        case '/poster':
          request.response.statusCode = 302;
          request.response.headers.set('location', '/actual?rev=1');
        case '/actual':
          request.response.write('image');
        case '/redirect':
          request.response.statusCode = 302;
          request.response.headers.set('location', '$external/image');
      }
    });
    final httpClient = http.Client();
    addTearDown(httpClient.close);
    final images = ArtworkFileService(client: httpClient);
    final headers = {
      fnMovieArtworkOriginHeader: base,
      fnMovieArtworkProfileHeader: 'first',
      'Authorization': _token,
    };
    final image = await images.get('$base/poster', headers: headers);
    expect(await image.content.transform(utf8.decoder).join(), 'image');
    await expectLater(
      images.get('$base/redirect', headers: headers),
      throwsFormatException,
    );
    expect(externalRequests, 0);
    final public = await images.get(
      '$external/image',
      headers: {fnMovieArtworkProfileHeader: 'first'},
    );
    await public.content.drain<void>();
    expect(externalRequests, 1);
    expect(
      artworkCacheKey('$base/poster', headers),
      isNot(
        artworkCacheKey('$base/poster', {
          ...headers,
          fnMovieArtworkProfileHeader: 'second',
        }),
      ),
    );
  });

  test(
    'playback signs each Range, writes once, and resumes from a fresh client',
    () async {
      final ranges = <String?>[];
      var current = 37;
      var updates = 0;
      var playInfoCalls = 0;
      final base = await _serve((request, body) async {
        _checkSignature(request, body);
        switch (request.uri.path) {
          case '/proxy/api/v1/play/info':
            playInfoCalls++;
            expect(jsonDecode(body), {'item_guid': 'ep'});
            _json(request, {
              'media_guid': 'media',
              'ts': current,
              'duration': 125,
            });
          case '/proxy/api/v1/stream':
            _json(request, {
              'video_stream': {'duration': 125},
              'direct_link_qualities': [
                {'url': '/index.m3u8', 'bitrate': 50},
                {'url': 'https://elsewhere.invalid/movie.mp4', 'bitrate': 60},
              ],
            });
          case '/proxy/api/v1/media/range/media':
            final range = request.headers.value('range');
            ranges.add(range);
            final start = range == 'bytes=4-7' ? 4 : 0;
            request.response.statusCode = 206;
            request.response.headers.set(
              'content-range',
              'bytes $start-${start + 3}/8',
            );
            request.response.headers.set('accept-ranges', 'bytes');
            request.response.headers.contentType = ContentType('video', 'mp4');
            request.response.contentLength = 4;
            request.response.write(start == 0 ? 'head' : 'data');
          case '/proxy/api/v1/play/record':
            final payload = jsonDecode(body) as Map;
            expect(
              payload.keys,
              unorderedEquals(['media_guid', 'item_guid', 'ts']),
            );
            expect(payload['media_guid'], 'media');
            expect(payload['item_guid'], 'ep');
            current = payload['ts'] as int;
            updates++;
            _json(request, {});
          case '/proxy/api/v1/play/list':
            _json(request, [
              {
                'item_guid': 'ep',
                'item': {'guid': 'ep', 'type': 'Episode', 'title': 'Episode'},
                'duration': 125,
              },
            ]);
          default:
            fail('Unexpected endpoint: ${request.uri.path}');
        }
      });
      final profile = _profile('$base/proxy');
      final client = FnMovieClient(server: profile);
      final source = await client.playbackSource(_user, 'ep');
      addTearDown(() => client.stopTranscoding(source.session));
      expect(source.startPosition.inSeconds, 37);
      expect(source.headers, isEmpty);
      expect(source.url, isNot(contains(_token)));
      final mediaUri = Uri.parse(source.url);
      expect(mediaUri.host, '127.0.0.1');
      expect(
        (await http.get(mediaUri.replace(path: '/invalid'))).statusCode,
        404,
      );
      for (final (range, contentRange, text) in [
        ('bytes=0-3', 'bytes 0-3/8', 'head'),
        ('bytes=4-7', 'bytes 4-7/8', 'data'),
      ]) {
        final response = await http.get(mediaUri, headers: {'Range': range});
        expect(response.statusCode, 206);
        expect(response.headers['content-range'], contentRange);
        expect(response.body, text);
      }
      expect(ranges, ['bytes=0-3', 'bytes=4-7']);
      const position = Duration(milliseconds: 64050);
      await client.reportPlaybackStopped(
        source.session,
        position: position,
        failed: false,
      );
      await client.stopTranscoding(source.session);
      await client.updatePlaybackPosition(
        _user,
        'ep',
        position: position,
        session: source.session,
      );
      expect(updates, 1);
      expect(
        playInfoCalls,
        1,
        reason: 'updates should reuse the negotiated media GUID',
      );
      final fresh = FnMovieClient(server: profile);
      expect(
        (await fresh.resume(_user)).single.playbackPosition!.inSeconds,
        64,
      );
      final resumed = await fresh.playbackSource(_user, 'ep');
      addTearDown(() => fresh.stopTranscoding(resumed.session));
      expect(resumed.startPosition.inSeconds, 64);
      final explicit = await fresh.playbackSource(
        _user,
        'ep',
        startPosition: Duration.zero,
      );
      addTearDown(() => fresh.stopTranscoding(explicit.session));
      expect(explicit.startPosition, Duration.zero);
    },
  );

  test(
    'a direct link redirect cannot leak credentials or change the chosen file',
    () async {
      var directRequests = 0;
      var externalRequests = 0;
      final external = await _serve((request, body) async {
        externalRequests++;
        request.response.write('unexpected');
      });
      final base = await _serve((request, body) async {
        _checkSignature(request, body);
        switch (request.uri.path) {
          case '/api/v1/play/info':
            _json(request, {'media_guid': 'media'});
          case '/api/v1/stream':
            _json(request, {
              'direct_link_qualities': [
                {'url': '/direct.mp4', 'bitrate': 60},
              ],
            });
          case '/direct.mp4':
            directRequests++;
            request.response.statusCode = 302;
            request.response.headers.set('location', '$external/file.mp4');
          case '/api/v1/media/range/media':
            request.response.statusCode = 206;
            request.response.headers.set('content-range', 'bytes 0-3/4');
            request.response.write('data');
          default:
            fail('Unexpected endpoint: ${request.uri.path}');
        }
      });
      final client = FnMovieClient(server: _profile(base));
      final source = await client.playbackSource(_user, 'movie');
      addTearDown(() => client.stopTranscoding(source.session));
      for (var i = 0; i < 2; i++) {
        final response = await http.get(
          Uri.parse(source.url),
          headers: {'Range': 'bytes=0-3'},
        );
        expect(response.statusCode, 206);
        expect(response.body, 'data');
      }
      expect(directRequests, 1);
      expect(externalRequests, 0);
    },
  );
}
