import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_playback_session.dart';
import 'package:sakuga/data/media_server/playback_models.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';

void main() {
  const server = ServerProfile(
    id: 'server',
    name: 'Server',
    baseUrl: 'https://media.example/jellyfin/',
    apiKey: 'secret',
  );

  test('maps typed browse options to Jellyfin query parameters', () async {
    final adapter = _PlaybackAdapter({'Items': [], 'TotalRecordCount': 90});
    final client = JellyfinClient(server: server, dio: _dio(adapter));
    final page = await client.items(
      'user-1',
      'library-1',
      startIndex: 60,
      limit: 30,
      types: {MediaType.movie, MediaType.video},
      sort: MediaSort.random,
    );
    expect(adapter.lastQuery['includeItemTypes'], 'Movie,Video');
    expect(adapter.lastQuery['sortBy'], 'Random');
    expect(adapter.lastQuery['startIndex'], 60);
    expect(adapter.lastQuery['limit'], 30);
    expect(page.totalRecordCount, 90);
  });

  test('negotiates a direct-play URL with auth and resume position', () async {
    final adapter = _PlaybackAdapter({
      'PlaySessionId': 'play-session',
      'MediaSources': [
        {
          'Id': 'media-source',
          'SupportsDirectPlay': true,
          'RequiredHttpHeaders': {'X-Required': 'yes'},
          'MediaStreams': [
            {
              'Type': 'Subtitle',
              'DeliveryUrl': '/Videos/item-1/Subtitles/2/Stream.ass',
              'DisplayTitle': '简体中文 ASS',
              'Language': 'chi',
            },
          ],
        },
      ],
    });
    final client = JellyfinClient(server: server, dio: _dio(adapter));

    final source = await client.playbackSource(
      'user-1',
      'item-1',
      startPosition: const Duration(seconds: 15),
    );

    expect(
      source.url,
      'https://media.example/jellyfin/Videos/item-1/stream'
      '?static=true&mediaSourceId=media-source&playSessionId=play-session',
    );
    expect(source.headers['Authorization'], contains('Token="secret"'));
    expect(source.headers['X-Required'], 'yes');
    expect(source.startPosition, const Duration(seconds: 15));
    expect(source.subtitles, hasLength(1));
    expect(
      source.subtitles.single.url,
      'https://media.example/jellyfin/Videos/item-1/Subtitles/2/Stream.ass',
    );
    expect(source.subtitles.single.title, '简体中文 ASS');
    expect(adapter.lastPath, '/Items/item-1/PlaybackInfo');
    expect(adapter.lastQuery['userId'], 'user-1');
    expect(adapter.lastBody['StartTimeTicks'], 150000000);
    expect(adapter.lastBody['DeviceProfile'], isA<Map<String, dynamic>>());
  });

  test('uses the server-provided transcoding URL unchanged', () async {
    final adapter = _PlaybackAdapter({
      'MediaSources': [
        {
          'Id': 'media-source',
          'SupportsDirectPlay': false,
          'TranscodingSubProtocol': 'hls',
          'TranscodingUrl': '/Videos/item-1/master.m3u8?MediaSourceId=source&token=value&StartTimeTicks=150000000',
        },
      ],
    });
    final client = JellyfinClient(server: server, dio: _dio(adapter));

    final source = await client.playbackSource(
      'user-1',
      'item-1',
      startPosition: const Duration(seconds: 15),
    );

    expect(
      source.url,
      'https://media.example/jellyfin/Videos/item-1/master.m3u8'
      '?MediaSourceId=source&token=value&StartTimeTicks=150000000',
    );
    expect(source.startPosition, const Duration(seconds: 15));
    expect(source.initialPosition, const Duration(seconds: 15));
    expect(source.positionOffset, Duration.zero);
    expect(
      (source.session as JellyfinPlaybackSession).playMethod,
      PlayMethod.transcode,
    );
    expect(adapter.lastBody['StartTimeTicks'], 150000000);
  });

  test('offsets zero-based non-HLS transcoding progress', () async {
    final adapter = _PlaybackAdapter({
      'MediaSources': [
        {
          'Id': 'media-source',
          'SupportsDirectPlay': false,
          'TranscodingSubProtocol': 'http',
          'TranscodingUrl': '/Videos/item-1/stream.ts?StartTimeTicks=90000000',
        },
      ],
    });
    final client = JellyfinClient(server: server, dio: _dio(adapter));

    final source = await client.playbackSource(
      'user-1',
      'item-1',
      startPosition: const Duration(seconds: 9),
    );

    expect(source.startPosition, Duration.zero);
    expect(source.initialPosition, const Duration(seconds: 9));
    expect(source.positionOffset, const Duration(seconds: 9));
  });

  test(
    'reports playback start, progress and stop with session metadata',
    () async {
      final adapter = _PlaybackAdapter({
        'PlaySessionId': 'play-session',
        'MediaSources': [
          {'Id': 'media-source', 'SupportsDirectPlay': true},
        ],
      });
      final client = JellyfinClient(server: server, dio: _dio(adapter));
      final source = await client.playbackSource('user-1', 'item-1');

      await client.reportPlaybackStarted(
        source.session,
        position: const Duration(seconds: 1),
        isPaused: false,
        volume: 75,
      );
      await client.reportPlaybackProgress(
        source.session,
        position: const Duration(seconds: 2),
        isPaused: true,
        volume: 0,
      );
      await client.reportPlaybackStopped(
        source.session,
        position: const Duration(seconds: 3),
        failed: false,
        volume: 50,
      );
      await client.updatePlaybackPosition(
        'user-1',
        'item-1',
        position: const Duration(seconds: 3),
      );

      expect(
        adapter.requests.map((request) => request.path),
        containsAllInOrder([
          '/Items/item-1/PlaybackInfo',
          '/Sessions/Playing',
          '/Sessions/Playing/Progress',
          '/Sessions/Playing/Stopped',
          '/UserItems/item-1/UserData',
        ]),
      );
      final started = adapter.requests[1].data as Map<String, dynamic>;
      expect(adapter.requests[1].connectTimeout, const Duration(seconds: 3));
      expect(adapter.requests[1].receiveTimeout, const Duration(seconds: 3));
      expect(started['ItemId'], 'item-1');
      expect(started['MediaSourceId'], 'media-source');
      expect(started['PlaySessionId'], 'play-session');
      expect(started['PositionTicks'], 10000000);
      expect(started['PlayMethod'], 'DirectPlay');
      expect(started['IsPaused'], isFalse);
      expect(started['VolumeLevel'], 75);

      final progress = adapter.requests[2].data as Map<String, dynamic>;
      expect(progress['PositionTicks'], 20000000);
      expect(progress['IsPaused'], isTrue);
      expect(progress['IsMuted'], isTrue);

      final stopped = adapter.requests[3].data as Map<String, dynamic>;
      expect(stopped['PositionTicks'], 30000000);
      expect(stopped['Failed'], isFalse);

      final userData = adapter.requests[4];
      expect(userData.queryParameters['userId'], 'user-1');
      expect(
        (userData.data as Map<String, dynamic>)['PlaybackPositionTicks'],
        30000000,
      );
    },
  );

  test(
    'falls back to legacy user data endpoint on 404 and forwards played state',
    () async {
      final adapter = _PlaybackAdapter(
        const {},
        notFoundPaths: {'/UserItems/item-1/UserData'},
      );
      final client = JellyfinClient(server: server, dio: _dio(adapter));

      await client.updatePlaybackPosition(
        'user-1',
        'item-1',
        position: Duration.zero,
        played: true,
      );

      expect(adapter.requests.map((request) => request.path), [
        '/UserItems/item-1/UserData',
        '/Users/user-1/Items/item-1/UserData',
      ]);
      final legacy = adapter.requests.last.data as Map<String, dynamic>;
      expect(legacy['PlaybackPositionTicks'], 0);
      expect(legacy['Played'], isTrue);
    },
  );
}

Dio _dio(HttpClientAdapter adapter) => Dio(
  BaseOptions(
    baseUrl: 'https://media.example/jellyfin/',
    headers: {
      'Authorization':
          'MediaBrowser Token="secret", Client="Sakuga", Device="Sakuga", '
          'DeviceId="sakuga", Version="0.1.0"',
    },
  ),
)..httpClientAdapter = adapter;

class _PlaybackAdapter implements HttpClientAdapter {
  _PlaybackAdapter(this.response, {this.notFoundPaths = const {}});

  final Map<String, dynamic> response;
  final Set<String> notFoundPaths;
  String? lastPath;
  Map<String, dynamic> lastQuery = const {};
  Map<String, dynamic> lastBody = const {};
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    lastPath = options.path;
    lastQuery = options.queryParameters;
    final body = options.data;
    lastBody = body is Map<String, dynamic> ? body : const {};
    if (notFoundPaths.contains(options.path)) {
      return ResponseBody.fromString('', 404);
    }
    final hasResponse =
        options.method == 'GET' || options.path.endsWith('/PlaybackInfo');
    return ResponseBody.fromString(
      hasResponse ? jsonEncode(response) : '',
      hasResponse ? 200 : 204,
      headers: {
        if (hasResponse) Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
