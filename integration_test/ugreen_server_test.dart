import 'dart:typed_data';

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
  const seriesSearch = String.fromEnvironment('UGREEN_TEST_SERIES');
  const deviceId = 'sakuga-ugreen-live-test';

  testWidgets('UGREEN native playback opens and seeks in a movie and episode', (
    tester,
  ) async {
    expect(
      rawUrl.isNotEmpty && username.isNotEmpty,
      isTrue,
      reason: 'Provide live configuration via dart-define-from-file.',
    );
    var stage = 'sign-in';
    // Preserve the first failing stage even if native cleanup also stalls.
    String? failedStage;
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
      stage = 'browse';
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
      final seriesSample = seriesSearch.isEmpty
          ? await findSample(MediaType.series)
          : (await client.search(
              userId,
              seriesSearch,
            )).firstWhere((item) => item.isSeries);
      final series = await client.item(userId, seriesSample.id);
      final seasons = await client.seasons(userId, series.id);
      expect(seasons.isNotEmpty, isTrue);
      final episodes = await client.episodes(
        userId,
        series.id,
        seasonId: seasons.first.id,
      );
      expect(episodes.isNotEmpty, isTrue);
      stage = 'season details';
      final season = await client.item(userId, seasons.first.id);
      final artwork = {
        'movie poster': movie.poster,
        'series poster': series.poster,
        'series backdrop': series.backdrop,
        'season poster': season.poster,
        'season backdrop': season.backdrop,
        'episode thumbnail': episodes.first.poster,
      };
      for (final entry in artwork.entries) {
        stage = entry.key;
        final resource = entry.value!;
        final wide = entry.key.endsWith('backdrop');
        final image = await ArtworkFileService().get(
          resource.url(width: wide ? 1920 : 600),
          headers: resource.headers,
        );
        expect(image.statusCode, 200);
        final bytes = await image.content.expand((chunk) => chunk).toList();
        final codec = await decodeImageFromList(Uint8List.fromList(bytes));
        expect(codec.width, greaterThan(0));
        codec.dispose();
      }

      stage = 'initialize libmpv';
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
          stage = '${item.type.name} PlaybackInfo';
          final source = await client.playbackSource(userId, item.id);
          try {
            expect(Uri.parse(source.url).host, '127.0.0.1');
            stage = '${item.type.name} libmpv open';
            debugPrint(stage);
            await player
                .open(Media(source.url, httpHeaders: source.headers))
                .timeout(const Duration(seconds: 20));
            final duration = player.state.duration > Duration.zero
                ? player.state.duration
                : await player.stream.duration
                      .firstWhere((d) => d > Duration.zero)
                      .timeout(const Duration(seconds: 30));
            stage = '${item.type.name} libmpv seek';
            debugPrint(stage);
            final target = duration ~/ 2;
            await player.seek(target).timeout(const Duration(seconds: 15));
            bool near(Duration position) =>
                (position - target).abs() < const Duration(seconds: 3);
            if (!near(player.state.position)) {
              await player.stream.position
                  .firstWhere(near)
                  .timeout(const Duration(seconds: 20));
            }
          } catch (_) {
            failedStage = stage;
            rethrow;
          } finally {
            try {
              await player.stop().timeout(const Duration(seconds: 5));
            } finally {
              await client.stopTranscoding(source.session);
            }
          }
        }
      } finally {
        await player.dispose().timeout(const Duration(seconds: 5));
      }
    } catch (error) {
      // Test output must not disclose server responses, URLs or credentials.
      fail(
        'UGREEN live check failed at ${failedStage ?? stage} (${error.runtimeType}).',
      );
    }
  }, skip: !enabled);
}
