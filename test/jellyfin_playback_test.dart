import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/server_profile.dart';

void main() {
  const server = ServerProfile(
    id: 'server',
    name: 'Server',
    baseUrl: 'https://media.example/jellyfin/',
    apiKey: 'secret',
  );

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
      startTimeTicks: 150000000,
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
          'TranscodingUrl':
              '/Videos/item-1/master.m3u8?MediaSourceId=source&token=value',
        },
      ],
    });
    final client = JellyfinClient(server: server, dio: _dio(adapter));

    final source = await client.playbackSource('user-1', 'item-1');

    expect(
      source.url,
      'https://media.example/jellyfin/Videos/item-1/master.m3u8'
      '?MediaSourceId=source&token=value',
    );
    expect(source.startPosition, Duration.zero);
  });
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
  _PlaybackAdapter(this.response);

  final Map<String, dynamic> response;
  String? lastPath;
  Map<String, dynamic> lastQuery = const {};
  Map<String, dynamic> lastBody = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastQuery = options.queryParameters;
    final body = options.data;
    lastBody = body is Map<String, dynamic> ? body : const {};
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
