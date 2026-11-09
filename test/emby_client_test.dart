import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/data/emby/emby_client.dart';
import 'package:sakuga/data/emby/emby_playback_session.dart';
import 'package:sakuga/data/emby/emby_probe.dart';
import 'package:sakuga/data/emby/emby_protocol.dart';
import 'package:sakuga/data/jellyfin/jellyfin_playback_session.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/playback_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Emby',
  baseUrl: 'https://media.example/proxy/emby/',
  type: MediaServerType.emby,
  accessToken: 'secret',
  userId: 'user',
  username: 'Alice',
  deviceId: 'device',
);
const _fields =
    'RunTimeTicks,PrimaryImageAspectRatio,ImageTags,UserData,ChildCount,RecursiveItemCount';
const _images = 'Primary,Backdrop,Logo';

void main() {
  test('normalizes roots and resolves returned Emby paths only once', () {
    for (final root in [
      'https://media.example/proxy',
      'https://media.example/proxy/emby/',
      'https://media.example/proxy/emby/emby',
    ]) {
      expect(embyApiBaseUrl(root), 'https://media.example/proxy/emby');
      for (final path in [
        '/emby/Videos/movie/master.m3u8?x=1',
        '/proxy/emby/Videos/movie/master.m3u8?x=1',
        'Videos/movie/master.m3u8?x=1',
        '/Videos/movie/master.m3u8?x=1',
      ]) {
        expect(
          resolveEmbyUrl(root, path),
          'https://media.example/proxy/emby/Videos/movie/master.m3u8?x=1',
        );
      }
    }
    expect(
      resolveEmbyUrl(_server.baseUrl, '//cdn.example/video'),
      'https://cdn.example/video',
    );
    expect(
      () => resolveEmbyUrl(_server.baseUrl, 'file:///private/video'),
      throwsFormatException,
    );
  });

  test(
    'users fetches only authenticated user with Emby token headers',
    () async {
      final adapter = _Adapter({'Id': 'user', 'Name': 'Alice'});
      final client = _client(adapter);
      final users = await client.users();
      expect(users.single.name, 'Alice');
      expect(
        adapter.last.uri.toString(),
        'https://media.example/proxy/emby/Users/user',
      );
      expect(adapter.last.headers['X-Emby-Token'], 'secret');
      expect(
        adapter.last.headers['X-Emby-Authorization'],
        'Emby Client="Sakuga", Device="Sakuga", DeviceId="device", Version="0.1.0"',
      );
      expect(adapter.last.headers.containsKey('Authorization'), isFalse);
      expect(adapter.last.followRedirects, isFalse);
      expect(client.isConfigured, isTrue);
      final unconfigured = EmbyClient(
        server: _server.copyWith(accessToken: ''),
        dio: Dio()..httpClientAdapter = adapter,
      );
      expect(unconfigured.isConfigured, isFalse);
      final count = adapter.requests.length;
      await expectLater(unconfigured.users(), throwsA(isA<AppException>()));
      expect(adapter.requests.length, count);
    },
  );

  test(
    'browse uses user-scoped endpoints and preserves typed filters',
    () async {
      final adapter = _Adapter({
        'Items': [
          {
            'Id': 'movie',
            'Name': 'Movie',
            'Type': 'Movie',
            'ImageTags': {'Primary': 'tag'},
            'UserData': {'PlaybackPositionTicks': 120000000},
          },
        ],
        'TotalRecordCount': 80,
      });
      final client = _client(adapter);
      final page = await client.items(
        'user',
        'library',
        startIndex: 60,
        limit: 20,
        types: {MediaType.movie},
        genre: 'Anime',
        year: 2025,
        isPlayed: false,
        sort: MediaSort.rating,
        descending: true,
      );
      _expectUri(adapter.last, '/Users/user/Items', {
        'userId': 'user',
        'parentId': 'library',
        'recursive': 'true',
        'includeItemTypes': 'Movie',
        'Genres': 'Anime',
        'isPlayed': 'false',
        'years': '2025',
        'sortBy': 'CommunityRating',
        'sortOrder': 'Descending',
        'fields': _fields,
        'enableImageTypes': _images,
        'imageTypeLimit': '1',
        'startIndex': '60',
        'limit': '20',
      });
      expect(page.totalRecordCount, 80);
      expect(page.items.single.playbackPosition, const Duration(seconds: 12));
      expect(
        page.items.single.poster!.url(),
        'https://media.example/proxy/emby/Items/movie/Images/Primary?maxWidth=600&tag=tag',
      );
      expect(page.items.single.poster!.headers['X-Emby-Token'], 'secret');
      adapter.response = {
        'Items': [
          {'Id': 'library', 'Name': 'TV', 'CollectionType': 'tvshows'},
        ],
      };
      expect((await client.views('user')).single.isTvShows, isTrue);
      _expectUri(adapter.last, '/Users/user/Views', {});
      adapter.response = {'Id': 'movie', 'Type': 'Movie'};
      await client.item('user', 'movie');
      expect(adapter.last.uri.path, '/proxy/emby/Users/user/Items/movie');
      expect(adapter.last.uri.queryParameters['userId'], 'user');
    },
  );

  test(
    'resume latest search random seasons episodes and filters use Emby routes',
    () async {
      final adapter = _Adapter({'Items': []});
      final client = _client(adapter);
      await client.resume('user', limit: 3);
      _expectUri(adapter.last, '/Users/user/Items/Resume', {
        'limit': '3',
        'fields': _fields,
        'enableImageTypes': _images,
        'imageTypeLimit': '1',
        'mediaTypes': 'Video',
      });
      adapter.response = [];
      await client.latest('user', limit: 4);
      _expectUri(adapter.last, '/Users/user/Items/Latest', {
        'limit': '4',
        'fields': _fields,
        'enableImageTypes': _images,
        'imageTypeLimit': '1',
      });
      adapter.response = {'Items': []};
      await client.search('user', 'anime space', limit: 5);
      _expectUri(adapter.last, '/Users/user/Items', {
        'userId': 'user',
        'recursive': 'true',
        'searchTerm': 'anime space',
        'includeItemTypes': 'Movie,Series,Video',
        'sortBy': 'SortName',
        'sortOrder': 'Ascending',
        'fields': _fields,
        'enableImageTypes': _images,
        'imageTypeLimit': '1',
        'limit': '5',
      });
      await client.randomItems('user');
      expect(adapter.last.uri.path, '/proxy/emby/Users/user/Items');
      expect(adapter.last.uri.queryParameters['sortBy'], 'Random');
      await client.seasons('user', 'series');
      _expectUri(adapter.last, '/Shows/series/Seasons', {
        'userId': 'user',
        'fields': _fields,
        'enableImageTypes': _images,
        'imageTypeLimit': '1',
      });
      await client.episodes('user', 'series', seasonId: 'season');
      _expectUri(adapter.last, '/Shows/series/Episodes', {
        'userId': 'user',
        'seasonId': 'season',
        'fields': '$_fields,Overview',
        'enableImageTypes': _images,
        'imageTypeLimit': '1',
      });
      adapter.response = {
        'Items': [
          {'Name': 'Anime'},
        ],
      };
      expect(await client.genres('user', 'library'), ['Anime']);
      _expectUri(adapter.last, '/Genres', {
        'UserId': 'user',
        'ParentId': 'library',
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series,Episode,Video,MusicVideo',
      });
      adapter.response = {
        'Items': [
          {'Name': '2024'},
          {'Name': '2025'},
          {'Name': '2024'},
          {'Name': '0'},
          {'Name': 'invalid'},
          {},
        ],
      };
      expect(await client.years('user', 'library'), [2025, 2024]);
      _expectUri(adapter.last, '/Years', {
        'userId': 'user',
        'parentId': 'library',
        'recursive': 'true',
        'includeItemTypes': 'Movie,Series,Video,MusicVideo',
        'enableImages': 'false',
        'enableUserData': 'false',
        'sortBy': 'SortName',
        'sortOrder': 'Descending',
      });
    },
  );

  test(
    'direct playback negotiates source subtitles and session reports',
    () async {
      final adapter = _Adapter(
        _playback({
          'SupportsDirectPlay': true,
          'MediaStreams': [
            {
              'Type': 'Subtitle',
              'Codec': 'srt',
              'DeliveryMethod': 'External',
              'DeliveryUrl': '/emby/Videos/movie/source/Subtitles/2/Stream.srt',
              'Language': 'eng',
            },
            {
              'Type': 'Subtitle',
              'Codec': 'pgssub',
              'DeliveryMethod': 'Embed',
              'DeliveryUrl': '/bad',
            },
          ],
        }),
      );
      final client = _client(adapter);
      final source = await client.playbackSource(
        'user',
        'movie',
        startPosition: const Duration(seconds: 30),
      );
      _expectUri(adapter.last, '/Items/movie/PlaybackInfo', {'userId': 'user'});
      expect(adapter.last.method, 'POST');
      expect((adapter.last.data as Map)['StartTimeTicks'], 300000000);
      expect(
        source.url,
        'https://media.example/proxy/emby/Videos/movie/stream?static=true&mediaSourceId=source&playSessionId=session&api_key=secret',
      );
      expect(source.headers.containsKey('X-Emby-Token'), isFalse);
      expect(source.startPosition, const Duration(seconds: 30));
      expect(source.session, isA<EmbyPlaybackSession>());
      expect(
        source.subtitles.single.url,
        'https://media.example/proxy/emby/Videos/movie/source/Subtitles/2/Stream.srt?api_key=secret',
      );
      expect(source.subtitles.single.language, 'eng');
      adapter.response = {};
      await client.reportPlaybackStarted(
        source.session,
        position: const Duration(seconds: 30),
        isPaused: false,
      );
      _expectUri(adapter.last, '/Sessions/Playing', {});
      expect((adapter.last.data as Map)['PlayMethod'], 'DirectPlay');
      await client.reportPlaybackProgress(
        source.session,
        position: const Duration(seconds: 35),
        isPaused: true,
        volume: 0,
      );
      _expectUri(adapter.last, '/Sessions/Playing/Progress', {});
      expect((adapter.last.data as Map)['PositionTicks'], 350000000);
      expect((adapter.last.data as Map)['IsMuted'], isTrue);
      await client.reportPlaybackStopped(
        source.session,
        position: const Duration(seconds: 40),
        failed: true,
      );
      _expectUri(adapter.last, '/Sessions/Playing/Stopped', {});
      expect((adapter.last.data as Map)['Failed'], isTrue);
      await expectLater(
        client.reportPlaybackStarted(
          const JellyfinPlaybackSession(
            itemId: 'movie',
            mediaSourceId: '',
            playSessionId: '',
            playMethod: PlayMethod.directPlay,
          ),
          position: Duration.zero,
          isPaused: false,
        ),
        throwsArgumentError,
      );
    },
  );

  test('missing subtitle URLs use documented text endpoint and keep bitmap tracks embedded', () async {
    final adapter = _Adapter(
      _playback({
        'SupportsDirectPlay': true,
        'MediaStreams': [
          {
            'Type': 'Subtitle',
            'Codec': 'subrip',
            'Index': 3,
            'SupportsExternalStream': true,
          },
          {'Type': 'Subtitle', 'Codec': 'pgssub', 'Index': 4},
          {
            'Type': 'Subtitle',
            'Codec': 'ass',
            'Index': 5,
            'SupportsExternalStream': false,
          },
        ],
      }),
    );
    final source = await _client(adapter).playbackSource('user', 'movie');
    expect(
      source.subtitles.single.url,
      'https://media.example/proxy/emby/Videos/movie/source/Subtitles/3/0/Stream.srt?CopyTimestamps=true&api_key=secret',
    );
    expect(source.headers, isEmpty);
  });

  test('direct stream and transcoding keep resume semantics', () async {
    final adapter = _Adapter(_playback({'SupportsDirectStream': true}));
    final client = _client(adapter);
    final direct = await client.playbackSource('user', 'movie');
    expect(
      direct.url,
      'https://media.example/proxy/emby/Videos/movie/stream?static=false&mediaSourceId=source&playSessionId=session&api_key=secret',
    );
    expect(
      (direct.session as EmbyPlaybackSession).playMethod,
      PlayMethod.directStream,
    );
    adapter.response = _playback({
      'TranscodingUrl':
          '/emby/Videos/movie/master.m3u8?StartTimeTicks=300000000',
      'TranscodingSubProtocol': 'hls',
    });
    final hls = await client.playbackSource(
      'user',
      'movie',
      startPosition: const Duration(seconds: 30),
    );
    expect(
      hls.url,
      'https://media.example/proxy/emby/Videos/movie/master.m3u8?StartTimeTicks=300000000&api_key=secret',
    );
    expect(hls.startPosition, const Duration(seconds: 30));
    expect(hls.positionOffset, Duration.zero);
    adapter.response = _playback({
      'TranscodingUrl': 'Videos/movie/stream.ts?StartTimeTicks=300000000',
    });
    final transcode = await client.playbackSource(
      'user',
      'movie',
      startPosition: const Duration(seconds: 30),
    );
    expect(transcode.startPosition, Duration.zero);
    expect(transcode.initialPosition, const Duration(seconds: 30));
    expect(transcode.positionOffset, const Duration(seconds: 30));
    expect(transcode.playMethod, PlayMethod.transcode);
  });

  test(
    'bitrate cap reaches PlaybackInfo and transcoding is cleaned up',
    () async {
      final adapter = _Adapter(
        _playback({
          'TranscodingUrl': '/videos/movie/master.m3u8?VideoBitrate=1400000',
          'TranscodingSubProtocol': 'hls',
        }),
      );
      final client = _client(adapter);
      final source = await client.playbackSource(
        'user',
        'movie',
        maxStreamingBitrate: 1500000,
        maxVideoHeight: 480,
      );
      final body = adapter.last.data as Map<String, dynamic>;
      expect(body['MaxStreamingBitrate'], 1500000);
      expect(body['IsPlayback'], isTrue);
      expect(
        (body['DeviceProfile'] as Map<String, dynamic>)['MaxStaticBitrate'],
        1500000,
      );
      final conditions =
          ((body['DeviceProfile'] as Map<String, dynamic>)['CodecProfiles']
                      as List)
                  .single['Conditions']
              as List;
      expect(conditions.single['Value'], '480');
      // The Emby wrapper keeps the negotiated method.
      expect(source.playMethod, PlayMethod.transcode);

      await client.stopTranscoding(source.session);
      expect(adapter.last.method, 'DELETE');
      _expectUri(adapter.last, '/Videos/ActiveEncodings', {
        'deviceId': 'device',
        'playSessionId': 'session',
      });

      adapter.requests.clear();
      adapter.response = _playback({'SupportsDirectPlay': true});
      final direct = await client.playbackSource('user', 'movie');
      expect(direct.playMethod, PlayMethod.directPlay);
      await client.stopTranscoding(direct.session);
      expect(adapter.requests.map((request) => request.method), ['POST']);
    },
  );

  test('external media receives no server authentication headers or subtitle token', () async {
    final adapter = _Adapter(
      _playback({
        'TranscodingUrl': 'https://cdn.example/video.m3u8?quality=1',
        'RequiredHttpHeaders': {
          'Authorization': 'server-secret',
          'X-Emby-Token': 'server-secret',
          'Referer': 'https://media.example/',
        },
        'MediaStreams': [
          {
            'Type': 'Subtitle',
            'DeliveryUrl': 'https://cdn.example/subtitle.srt',
          },
        ],
      }),
    );
    final source = await _client(adapter).playbackSource('user', 'movie');
    expect(source.url, 'https://cdn.example/video.m3u8?quality=1');
    expect(source.headers, {'Referer': 'https://media.example/'});
    expect(source.subtitles.single.url, 'https://cdn.example/subtitle.srt');
  });

  test(
    'external subtitles cannot inherit authenticated stream headers',
    () async {
      final adapter = _Adapter(
        _playback({
          'SupportsDirectPlay': true,
          'MediaStreams': [
            {
              'Type': 'Subtitle',
              'DeliveryUrl': 'https://cdn.example/subtitle.srt',
            },
            {
              'Type': 'Subtitle',
              'DeliveryUrl': '/emby/Videos/movie/Subtitles/2/Stream.srt',
            },
          ],
        }),
      );
      final source = await _client(adapter).playbackSource('user', 'movie');
      expect(source.subtitles, hasLength(2));
      expect(
        source.headers.keys.any(
          (key) => key.toLowerCase().startsWith('x-emby-'),
        ),
        isFalse,
      );
      expect(source.subtitles.first.url, 'https://cdn.example/subtitle.srt');
      expect(
        Uri.parse(source.subtitles.last.url).queryParameters['api_key'],
        'secret',
      );
    },
  );

  test(
    'server token is removed from external URLs without rewriting signed URLs',
    () async {
      final adapter = _Adapter(
        _playback({
          'TranscodingUrl': 'https://cdn.example/video?api_key=secret',
        }),
      );
      final client = _client(adapter);
      expect(
        (await client.playbackSource('user', 'movie')).url,
        'https://cdn.example/video',
      );
      adapter.response = _playback({
        'TranscodingUrl': 'https://cdn.example/video?api_key=secret&quality=1',
      });
      expect(
        (await client.playbackSource('user', 'movie')).url,
        'https://cdn.example/video?quality=1',
      );
      adapter.response = _playback({
        'TranscodingUrl': 'https://cdn.example/video?sig=a%2fb&x=1&x=2',
      });
      expect(
        (await client.playbackSource('user', 'movie')).url,
        'https://cdn.example/video?sig=a%2fb&x=1&x=2',
      );
      expect(
        embyApiBaseUrl('https://media.example/proxy?api_key=secret#x'),
        'https://media.example/proxy/emby',
      );
    },
  );

  test(
    'opening live malformed and server-rejected sources fail explicitly',
    () async {
      final adapter = _Adapter({});
      final client = _client(adapter);
      for (final source in [
        {'SupportsDirectPlay': true, 'RequiresOpening': true},
        {'SupportsDirectPlay': true, 'LiveStreamId': 'live'},
        {'SupportsDirectPlay': true, 'IsInfiniteStream': true},
        <String, dynamic>{},
      ]) {
        adapter.response = _playback(source);
        await expectLater(
          client.playbackSource('user', 'movie'),
          throwsA(isA<AppException>()),
        );
      }
      adapter.response = {'ErrorCode': 'NoCompatibleStream'};
      await expectLater(
        client.playbackSource('user', 'movie'),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('progress and watched changes use scoped Emby user endpoints', () async {
    final adapter = _Adapter({});
    final client = _client(adapter);
    await client.updatePlaybackPosition(
      'user',
      'movie',
      position: const Duration(seconds: 42),
      played: false,
    );
    _expectUri(adapter.last, '/Users/user/Items/movie/UserData', {});
    expect(adapter.last.method, 'POST');
    expect((adapter.last.data as Map)['PlaybackPositionTicks'], 420000000);
    expect((adapter.last.data as Map)['Played'], isFalse);
    expect(
      DateTime.parse((adapter.last.data as Map)['LastPlayedDate'] as String)
          .isUtc,
      isTrue,
    );
    await client.setPlayed('user', 'movie', played: true);
    _expectUri(adapter.last, '/Users/user/PlayedItems/movie', {});
    expect(adapter.last.method, 'POST');
    await client.setPlayed('user', 'movie', played: false);
    expect(adapter.last.method, 'DELETE');
    adapter.status = 404;
    final before = adapter.requests.length;
    await expectLater(
      client.updatePlaybackPosition('user', 'movie', position: Duration.zero),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests.length, before + 1);
  });

  test(
    'probe uses public info before login and maps authenticated failures',
    () async {
      final adapter = _Adapter({
        'ServerName': 'Emby',
        'Version': '4.9',
        'Id': 'remote',
      });
      final probe = EmbyProbe(dio: Dio()..httpClientAdapter = adapter);
      final info = await probe.probe('https://media.example/proxy/emby/');
      expect(info.id, 'remote');
      _expectUri(adapter.last, '/System/Info/Public', {});
      expect(adapter.last.headers.containsKey('X-Emby-Token'), isFalse);
      await probe.probe('https://media.example/proxy', apiKey: 'token');
      _expectUri(adapter.last, '/System/Info', {});
      expect(adapter.last.headers['X-Emby-Token'], 'token');
      adapter.status = 401;
      await expectLater(
        probe.probe(_server.baseUrl),
        throwsA(
          isA<AppException>().having((e) => e.kind, 'kind', FailureKind.auth),
        ),
      );
    },
  );
}

Map<String, dynamic> _playback(Map<String, dynamic> source) => {
  'PlaySessionId': 'session',
  'MediaSources': [
    {'Id': 'source', ...source},
  ],
};
EmbyClient _client(_Adapter adapter) =>
    EmbyClient(server: _server, dio: Dio()..httpClientAdapter = adapter);
void _expectUri(
  RequestOptions request,
  String path,
  Map<String, String> query,
) {
  final expected = Uri.parse('https://media.example/proxy/emby$path')
      .replace(queryParameters: query.isEmpty ? null : query);
  expect(request.uri.toString(), expected.toString());
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.response);
  Object response;
  int status = 200;
  final requests = <RequestOptions>[];
  RequestOptions get last => requests.last;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
