import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sakuga/data/jellyfin/jellyfin_auth.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/playback_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/features/player/player_buffer.dart';
import 'package:sakuga/features/player/player_subtitle_rendering.dart';

/// Optional live check that the buffer preference changes how much mpv
/// actually reads ahead, using the app's player configuration and the local
/// Docker Jellyfin fixture (Big Buck Bunny, about 62 MiB, direct play).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const mib = 1024 * 1024;

  testWidgets('buffer preference bounds the real forward cache', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    const baseUrl = String.fromEnvironment('JELLYFIN_TEST_URL');
    const deviceId = 'sakuga-live-buffer';
    final auth = await JellyfinAuthService().authenticate(
      baseUrl: baseUrl,
      username: const String.fromEnvironment('JELLYFIN_TEST_USERNAME'),
      password: const String.fromEnvironment('JELLYFIN_TEST_PASSWORD'),
      deviceId: deviceId,
    );
    final client = JellyfinClient(
      server: ServerProfile(
        id: 'live-buffer',
        name: 'Jellyfin Docker',
        baseUrl: baseUrl,
        accessToken: auth.accessToken,
        userId: auth.userId,
        username: auth.username,
        deviceId: deviceId,
      ),
    );
    final movies = (await client.views(auth.userId))
        .firstWhere((view) => view.type == MediaLibraryType.movies);
    final movie = (await client.items(
      auth.userId,
      movies.id,
      types: {MediaType.movie},
      limit: 1,
    )).items.single;

    Future<({int bytes, double seconds})> measure(int bufferMiB) async {
      final player = Player(configuration: subtitlePlayerConfiguration);
      final video = VideoController(player);
      final native = player.platform as NativePlayer;
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 320,
              height: 180,
              child: Video(controller: video, controls: NoVideoControls),
            ),
          ),
        );
        await native.setProperty('ao', 'null');
        await applyPlaybackBuffer(native.setProperty, bufferMiB);
        final source = await client.playbackSource(auth.userId, movie.id);
        expect(source.playMethod, PlayMethod.directPlay);
        final started = player.stream.position
            .firstWhere((p) => p > Duration.zero)
            .timeout(const Duration(seconds: 20));
        await player.open(Media(source.url, httpHeaders: source.headers));
        await started;
        await player.pause();

        var last = -1;
        var stable = 0;
        var state = const <String, dynamic>{};
        for (var i = 0; i < 60 && stable < 4; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final raw = await native.getProperty('demuxer-cache-state');
          state = raw.isEmpty
              ? const {}
              : jsonDecode(raw) as Map<String, dynamic>;
          final bytes = (state['fw-bytes'] as num?)?.toInt() ?? 0;
          stable = bytes == last ? stable + 1 : 0;
          last = bytes;
        }
        final seconds = (state['cache-duration'] as num?)?.toDouble() ?? 0;
        debugPrint(
          'BUFFER_LIVE $bufferMiB MiB: fw-bytes ${(last / mib).toStringAsFixed(1)} MiB, '
          'cached ${seconds.toStringAsFixed(0)} s, '
          'max-bytes ${await native.getProperty('demuxer-max-bytes')}, '
          'back-bytes ${await native.getProperty('demuxer-max-back-bytes')}, '
          'cache-on-disk ${await native.getProperty('cache-on-disk')}',
        );
        return (bytes: last, seconds: seconds);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await player.dispose();
      }
    }

    final standard = await measure(32);
    final large = await measure(128);
    // The 32 MiB limit binds on a ~62 MiB file: it fills close to, not past, it.
    expect(standard.bytes, inInclusiveRange(24 * mib, 34 * mib));
    // A larger preference reads well beyond the previous limit.
    expect(large.bytes, greaterThan(40 * mib));
    expect(large.seconds, greaterThan(standard.seconds));
  }, skip: !const bool.fromEnvironment('JELLYFIN_LIVE_TEST'));
}
