import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:sakuga/core/images/artwork_cache.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/ugreen/ugreen_auth.dart';
import 'package:sakuga/data/ugreen/ugreen_client.dart';
import 'package:sakuga/data/ugreen/ugreen_transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('UGREEN_LIVE_TEST');
  const rawUrl = String.fromEnvironment('UGREEN_TEST_URL');
  const username = String.fromEnvironment('UGREEN_TEST_USERNAME');
  const password = String.fromEnvironment('UGREEN_TEST_PASSWORD');
  const fingerprint = String.fromEnvironment('UGREEN_TEST_FINGERPRINT');
  const deviceId = 'sakuga-ugreen-live-test';

  testWidgets('UGREEN native playback opens and seeks in a movie and episode', (
    tester,
  ) async {
    expect(
      rawUrl.isNotEmpty && username.isNotEmpty,
      isTrue,
      reason: 'Provide live configuration via dart-define-from-file.',
    );
    try {
      final baseUrl = normalizeUgreenBaseUrl(rawUrl);
      final auth = await UgreenAuthService().authenticate(
        baseUrl: baseUrl,
        username: username,
        password: password,
        deviceId: deviceId,
        fingerprint: fingerprint,
      );
      final client = UgreenClient(
        server: ServerProfile(
          id: deviceId,
          name: 'UGREEN',
          baseUrl: baseUrl,
          type: MediaServerType.ugreen,
          deviceId: deviceId,
          username: auth.username,
          userId: auth.userId,
          accessToken: auth.accessToken,
          remoteServerId: auth.remoteServerId,
          certificateFingerprint: fingerprint,
        ),
      );
      final userId = auth.userId;
      final views = await client.views(userId);
      Future<MediaItem> findSample(MediaType type) async {
        for (final view in views) {
          final page = await client.items(
            userId,
            view.id,
            types: {type},
            limit: 1,
          );
          for (final item in page.items) {
            if (item.type == type) return item;
          }
        }
        throw StateError(
          'Add one completed movie and one series to the test library.',
        );
      }

      final movie = await client.item(
        userId,
        (await findSample(MediaType.movie)).id,
      );
      final series = await client.item(
        userId,
        (await findSample(MediaType.series)).id,
      );
      final seasons = await client.seasons(userId, series.id);
      expect(seasons.isNotEmpty, isTrue);
      final episodes = await client.episodes(
        userId,
        series.id,
        seasonId: seasons.first.id,
      );
      expect(episodes.isNotEmpty, isTrue);
      final poster = movie.poster!;
      final image = await ArtworkFileService().get(
        poster.url(),
        headers: poster.headers,
      );
      expect(image.statusCode, 200);
      expect((await image.content.first).isNotEmpty, isTrue);

      MediaKit.ensureInitialized();
      final player = Player();
      final controller = VideoController(player);
      try {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 640,
              height: 360,
              child: Video(controller: controller, controls: NoVideoControls),
            ),
          ),
        );
        await player.setVolume(0);
        for (final item in [movie, episodes.first]) {
          final source = await client.playbackSource(userId, item.id);
          try {
            expect(Uri.parse(source.url).host, '127.0.0.1');
            await player.open(Media(source.url, httpHeaders: source.headers));
            final duration = player.state.duration > Duration.zero
                ? player.state.duration
                : await player.stream.duration
                      .firstWhere((d) => d > Duration.zero)
                      .timeout(const Duration(seconds: 30));
            final target = duration ~/ 2;
            await player.pause();
            await player.seek(target);
            bool near(Duration position) =>
                (position - target).abs() < const Duration(seconds: 3);
            if (!near(player.state.position)) {
              await player.stream.position
                  .firstWhere(near)
                  .timeout(const Duration(seconds: 20));
            }
          } finally {
            try {
              await player.stop();
            } finally {
              await client.stopTranscoding(source.session);
            }
          }
        }
      } finally {
        await player.dispose();
      }
    } catch (error) {
      // Test output must not disclose server responses, URLs or credentials.
      fail('UGREEN live check failed (${error.runtimeType}).');
    }
  }, skip: !enabled);
}
