import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sakuga/data/jellyfin/jellyfin_auth.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/features/player/player_errors.dart';
import 'package:sakuga/features/player/player_subtitle_rendering.dart';

/// Optional live check of the playback error gate with real libmpv: an audio
/// output failure must not be shown as a playback failure, while a missing
/// stream must be.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recoverable mpv errors do not count as playback failures', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    const baseUrl = String.fromEnvironment('JELLYFIN_TEST_URL');
    const deviceId = 'sakuga-live-errors';
    final auth = await JellyfinAuthService().authenticate(
      baseUrl: baseUrl,
      username: const String.fromEnvironment('JELLYFIN_TEST_USERNAME'),
      password: const String.fromEnvironment('JELLYFIN_TEST_PASSWORD'),
      deviceId: deviceId,
    );
    final client = JellyfinClient(
      server: ServerProfile(
        id: 'live-errors',
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

    Future<({List<String> errors, List<String> fatal, Duration position})> run(
      String url,
      Map<String, String> headers, {
      bool brokenAudio = false,
    }) async {
      final player = Player(configuration: subtitlePlayerConfiguration);
      final video = VideoController(player);
      final native = player.platform as NativePlayer;
      final errors = <String>[];
      final fatal = <String>[];
      final gate = PlaybackErrorGate(
        isStopped: () async => isPlaybackAborted(
          idle: await native.getProperty('idle-active') == 'yes',
          endReached: await native.getProperty('eof-reached') == 'yes',
          position: player.state.position,
          duration: player.state.duration,
        ),
        onFatal: fatal.add,
      );
      final subscription = player.stream.error.listen((error) {
        errors.add(error);
        gate.report(error);
      });
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
        if (brokenAudio) {
          await native.setProperty('ao', 'alsa');
          await native.setProperty(
            'audio-device',
            'alsa/sakuga-missing-device',
          );
        } else {
          await native.setProperty('ao', 'null');
        }
        await player.open(Media(url, httpHeaders: headers));
        await Future<void>.delayed(const Duration(seconds: 5));
        return (errors: errors, fatal: fatal, position: player.state.position);
      } finally {
        gate.reset();
        await subscription.cancel();
        await tester.pumpWidget(const SizedBox());
        await player.dispose();
      }
    }

    final source = await client.playbackSource(auth.userId, movie.id);
    final audioFailure = await run(
      source.url,
      source.headers,
      brokenAudio: true,
    );
    debugPrint(
      'ERROR_GATE_LIVE audio failure: errors=${audioFailure.errors.length} '
      'fatal=${audioFailure.fatal.length} position=${audioFailure.position.inSeconds}s',
    );
    expect(
      audioFailure.errors,
      isNotEmpty,
      reason: 'mpv must report the device',
    );
    expect(audioFailure.fatal, isEmpty);
    expect(audioFailure.position, greaterThan(const Duration(seconds: 2)));

    final missing = await run(
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/Videos/00000000000000000000000000000000/stream?static=true',
      source.headers,
    );
    debugPrint(
      'ERROR_GATE_LIVE missing stream: errors=${missing.errors.length} '
      'fatal=${missing.fatal.length}',
    );
    expect(missing.errors, isNotEmpty);
    expect(missing.fatal, isNotEmpty);
  }, skip: !const bool.fromEnvironment('JELLYFIN_LIVE_TEST'));
}
