import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sakuga/data/emby/emby_auth.dart';
import 'package:sakuga/data/emby/emby_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_auth.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/media_browser/media_browser_client.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/playback_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';

/// Optional live check of manual quality switching against the local Docker
/// fixtures. Mirrors the player flow: direct play, renegotiate from the current
/// position with a bitrate cap, play the server HLS transcode in libmpv, then
/// stop the job through the explicit cleanup endpoint.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const deviceId = 'sakuga-live-quality';
  const cap = 720000;

  Future<int> ffmpegCount(String container) async {
    final result = await Process.run('docker', [
      'top',
      container,
      '-eo',
      'pid,args',
    ]);
    if (result.exitCode != 0) return -1;
    return '${result.stdout}'
        .split('\n')
        .where((line) => line.contains('ffmpeg') && line.contains('m3u8'))
        .length;
  }

  Future<void> exercise(
    WidgetTester tester, {
    required String label,
    required String container,
    required MediaBrowserClient client,
    required String userId,
  }) async {
    final libraries = await client.views(userId);
    final movies = libraries.firstWhere(
      (v) => v.type == MediaLibraryType.movies,
    );
    final movie = (await client.items(
      userId,
      movies.id,
      types: {MediaType.movie},
      limit: 1,
    )).items.single;

    final player = Player();
    final video = VideoController(player);
    final errors = <String>[];
    final subscription = player.stream.error.listen(errors.add);
    try {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 640,
            height: 360,
            child: Video(controller: video, controls: NoVideoControls),
          ),
        ),
      );
      // Audio output is irrelevant here and unavailable on headless hosts.
      await (player.platform as NativePlayer).setProperty('ao', 'null');
      await player.setVolume(0);

      final direct = await client.playbackSource(
        userId,
        movie.id,
        startPosition: const Duration(seconds: 30),
      );
      expect(direct.playMethod, PlayMethod.directPlay);
      final directReady = player.stream.position
          .firstWhere((p) => p.inSeconds >= 32)
          .timeout(const Duration(seconds: 30));
      await player.open(
        Media(
          direct.url,
          httpHeaders: direct.headers,
          start: direct.startPosition,
        ),
      );
      await directReady;
      await player.pause();
      final resumeAt = player.state.position;
      await client.reportPlaybackStopped(
        direct.session,
        position: resumeAt,
        failed: false,
        volume: 0,
      );
      await client.stopTranscoding(direct.session);

      final capped = await client.playbackSource(
        userId,
        movie.id,
        startPosition: resumeAt,
        maxStreamingBitrate: cap,
      );
      expect(capped.playMethod, PlayMethod.transcode, reason: label);
      expect(capped.url, contains('m3u8'), reason: label);
      expect(capped.startPosition, resumeAt);
      expect(capped.positionOffset, Duration.zero);
      final transcodeReady = player.stream.position
          .firstWhere((p) => p >= resumeAt + const Duration(seconds: 2))
          .timeout(const Duration(seconds: 60));
      await player.open(
        Media(
          capped.url,
          httpHeaders: capped.headers,
          start: capped.startPosition,
        ),
      );
      final played = await transcodeReady;
      expect(
        played - resumeAt,
        lessThan(const Duration(seconds: 10)),
        reason: 'Renegotiated stream must resume near the previous position',
      );
      await client.reportPlaybackStarted(
        capped.session,
        position: played,
        isPaused: false,
        volume: 0,
      );

      final playbackErrors = List.of(errors);
      expect(
        playbackErrors,
        isEmpty,
        reason: '$label: ${playbackErrors.join(' | ')}',
      );
      final running = await ffmpegCount(container);
      expect(running, greaterThan(0), reason: '$label must be transcoding');
      // Stop the player like leaving it would, then call the explicit cleanup
      // before the Stopped report so the check isolates the cleanup call.
      await player.stop();
      await client.stopTranscoding(capped.session);
      var remaining = running;
      if (running > 0) {
        for (var attempt = 0; attempt < 20 && remaining > 0; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          remaining = await ffmpegCount(container);
        }
        expect(remaining, 0, reason: '$label transcoding job must be stopped');
      }
      await client.reportPlaybackStopped(
        capped.session,
        position: played,
        failed: false,
        volume: 0,
      );
      // A resolution cap below the 180p source forces a scaled transcode.
      final scaled = await client.playbackSource(
        userId,
        movie.id,
        maxVideoHeight: 144,
      );
      expect(scaled.playMethod, PlayMethod.transcode, reason: label);
      final query = Uri.parse(scaled.url).queryParameters
          .map((key, value) => MapEntry(key.toLowerCase(), value));
      expect(query['maxheight'], '144', reason: label);
      await client.stopTranscoding(scaled.session);
      debugPrint(
        'QUALITY_LIVE_OK height cap 144 -> MaxHeight=${query['maxheight']}',
      );
      debugPrint(
        'QUALITY_LIVE_OK $label: direct play -> ${cap ~/ 1000} kbps transcode, '
        'resumed ${resumeAt.inMilliseconds} ms -> ${played.inMilliseconds} ms, '
        'ffmpeg $running -> $remaining',
      );
    } finally {
      await subscription.cancel();
      await tester.pumpWidget(const SizedBox());
      await player.dispose();
    }
  }

  testWidgets('Jellyfin manual bitrate cap renegotiates and cleans up', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    const baseUrl = String.fromEnvironment('JELLYFIN_TEST_URL');
    final auth = await JellyfinAuthService().authenticate(
      baseUrl: baseUrl,
      username: const String.fromEnvironment('JELLYFIN_TEST_USERNAME'),
      password: const String.fromEnvironment('JELLYFIN_TEST_PASSWORD'),
      deviceId: deviceId,
    );
    await exercise(
      tester,
      label: 'jellyfin',
      container: 'sakuga-jellyfin-test',
      userId: auth.userId,
      client: JellyfinClient(
        server: ServerProfile(
          id: 'live-quality',
          name: 'Jellyfin Docker',
          baseUrl: baseUrl,
          accessToken: auth.accessToken,
          userId: auth.userId,
          username: auth.username,
          deviceId: deviceId,
        ),
      ),
    );
  }, skip: !const bool.fromEnvironment('JELLYFIN_LIVE_TEST'));

  testWidgets('Emby manual bitrate cap renegotiates and cleans up', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    const baseUrl = String.fromEnvironment('EMBY_TEST_URL');
    final auth = await EmbyAuthService().authenticate(
      baseUrl: baseUrl,
      username: const String.fromEnvironment('EMBY_TEST_USERNAME'),
      password: const String.fromEnvironment('EMBY_TEST_PASSWORD'),
      deviceId: deviceId,
    );
    await exercise(
      tester,
      label: 'emby',
      container: 'sakuga-emby-test',
      userId: auth.userId,
      client: EmbyClient(
        server: ServerProfile(
          id: 'live-quality',
          name: 'Emby Docker',
          baseUrl: baseUrl,
          type: MediaServerType.emby,
          accessToken: auth.accessToken,
          userId: auth.userId,
          username: auth.username,
          remoteServerId: auth.remoteServerId,
          deviceId: deviceId,
        ),
      ),
    );
  }, skip: !const bool.fromEnvironment('EMBY_LIVE_TEST'));
}
