import 'package:dio/dio.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('JELLYFIN_LIVE_TEST');
  const baseUrl = String.fromEnvironment(
    'JELLYFIN_TEST_URL',
    defaultValue: 'http://127.0.0.1:18097',
  );
  const username = String.fromEnvironment(
    'JELLYFIN_TEST_USERNAME',
    defaultValue: 'sakuga',
  );
  const password = String.fromEnvironment('JELLYFIN_TEST_PASSWORD');

  testWidgets(
    'real Jellyfin user browses plays and synchronizes progress',
    (tester) async {
      expect(
        password.isNotEmpty,
        isTrue,
        reason: 'Provide JELLYFIN_TEST_PASSWORD through dart-define-from-file.',
      );
      String token = '';
      try {
        final auth = await JellyfinAuthService().authenticate(
          baseUrl: baseUrl,
          username: username,
          password: password,
          deviceId: 'sakuga-live-integration',
        );
        token = auth.accessToken;
        final client = JellyfinClient(
          server: ServerProfile(
            id: 'live-integration',
            name: 'Jellyfin Docker',
            baseUrl: baseUrl,
            type: MediaServerType.jellyfin,
            accessToken: token,
            userId: auth.userId,
            username: auth.username,
            remoteServerId: auth.remoteServerId,
            deviceId: 'sakuga-live-integration',
          ),
        );
        final users = await client.users();
        expect(users.single.id, auth.userId);
        final libraries = await client.views(auth.userId);
        expect(
          libraries.map((view) => view.type),
          containsAll([MediaLibraryType.movies, MediaLibraryType.tvShows]),
        );
        final movies = libraries.firstWhere(
          (view) => view.type == MediaLibraryType.movies,
        );
        final tv = libraries.firstWhere(
          (view) => view.type == MediaLibraryType.tvShows,
        );
        final moviePage = await client.items(
          auth.userId,
          movies.id,
          types: {MediaType.movie},
          limit: 1,
        );
        expect(moviePage.items, hasLength(1));
        final movie = await client.item(auth.userId, moviePage.items.single.id);
        expect(movie.runtime!.inMinutes, greaterThanOrEqualTo(6));
        expect(movie.poster, isNotNull);
        expect(await client.search(auth.userId, movie.name), isNotEmpty);
        expect(await client.latest(auth.userId), isNotEmpty);
        expect(await client.randomItems(auth.userId), isNotEmpty);
        final nextPage = await client.items(
          auth.userId,
          movies.id,
          types: {MediaType.movie},
          limit: 1,
          startIndex: 1,
        );
        expect(nextPage.items, isEmpty);
        final genres = await client.genres(auth.userId, movies.id);
        expect(genres, isNotEmpty);
        final seriesPage = await client.items(
          auth.userId,
          tv.id,
          types: {MediaType.series},
        );
        final series = seriesPage.items.single;
        final seasons = await client.seasons(auth.userId, series.id);
        expect(seasons, hasLength(1));
        final episodes = await client.episodes(
          auth.userId,
          series.id,
          seasonId: seasons.single.id,
        );
        expect(episodes.map((item) => item.indexNumber), unorderedEquals([1, 2]));
        expect(episodes.map((item) => item.parentIndexNumber), everyElement(1));
        expect(episodes.map((item) => item.name), unorderedEquals([
          '冒险的结束',
          '也不一定要是魔法…',
        ]));
        expect(seasons.single.name, '第 1 季');
        final imageDio = Dio();
        try {
          for (final artwork in [
            movie.poster,
            movie.backdrop,
            movie.logo,
            series.poster,
            series.backdrop,
            series.logo,
            seasons.single.poster,
            ...episodes.map((item) => item.poster),
          ]) {
            expect(artwork, isNotNull);
            final image = await imageDio.get<List<int>>(
              artwork!.url(width: 200),
              options: Options(
                headers: artwork.headers,
                responseType: ResponseType.bytes,
              ),
            );
            expect(image.data!.length, greaterThan(100));
          }
        } finally {
          imageDio.close();
        }
        MediaKit.ensureInitialized();
        final player = Player();
        final video = VideoController(player);
        final errors = <String>[];
        final errorSubscription = player.stream.error.listen(
          (error) => errors.add(redactPlaybackError(error, secrets: [token])),
        );
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
          await player.setVolume(0);
          for (final item in [movie, ...episodes]) {
            final source = await client.playbackSource(
              auth.userId,
              item.id,
              startPosition: const Duration(seconds: 30),
            );
            expect(
              source.headers.keys.any(
                (key) => key.toLowerCase() == 'x-emby-token',
              ),
              isFalse,
            );
            final durationReady = player.stream.duration
                .firstWhere((duration) => duration.inSeconds > 0)
                .timeout(const Duration(seconds: 20));
            await player.open(
              Media(
                source.url,
                httpHeaders: source.headers,
                start: source.startPosition,
              ),
            );
            final duration = await durationReady;
            expect(duration.inMinutes, greaterThanOrEqualTo(6));
            final positionReady = player.stream.position
                .firstWhere((position) => position.inSeconds >= 32)
                .timeout(const Duration(seconds: 20));
            await positionReady;
            await player.pause();
            final seekReady = player.stream.position
                .firstWhere((position) => position.inSeconds >= 119)
                .timeout(const Duration(seconds: 10));
            await player.seek(const Duration(seconds: 120));
            await seekReady;
            expect(source.subtitles, hasLength(2));
            final subtitleDio = Dio();
            try {
              for (final subtitle in source.subtitles) {
                final response = await subtitleDio.get<String>(
                  subtitle.url,
                  options: Options(responseType: ResponseType.plain),
                );
                expect(response.data!.isNotEmpty, isTrue);
                final native = player.platform as NativePlayer;
                await native.command([
                  'sub-add',
                  subtitle.url,
                  'select',
                  subtitle.title ?? 'Test captions',
                  subtitle.language ?? 'und',
                ]);
              }
            } finally {
              subtitleDio.close();
            }
            await client.reportPlaybackStarted(
              source.session,
              position: const Duration(seconds: 30),
              isPaused: false,
              volume: 0,
            );
            await client.reportPlaybackProgress(
              source.session,
              position: const Duration(seconds: 120),
              isPaused: true,
              volume: 0,
            );
            await client.reportPlaybackStopped(
              source.session,
              position: const Duration(seconds: 120),
              failed: false,
              volume: 0,
            );
            await client.updatePlaybackPosition(
              auth.userId,
              item.id,
              position: const Duration(seconds: 120),
              played: false,
            );
            final refreshed = await client.item(auth.userId, item.id);
            expect(refreshed.playbackPosition!.inSeconds, 120);
            expect(
              (await client.resume(auth.userId)).map((item) => item.id),
              contains(item.id),
            );
            await client.setPlayed(auth.userId, item.id, played: true);
            expect((await client.item(auth.userId, item.id)).played, isTrue);
            await client.setPlayed(auth.userId, item.id, played: false);
            expect((await client.item(auth.userId, item.id)).played, isFalse);
            // Leave a useful resume entry for the user to inspect after the test.
            await client.updatePlaybackPosition(
              auth.userId,
              item.id,
              position: const Duration(seconds: 120),
              played: false,
            );
            debugPrint(
              'JELLYFIN_LIVE_OK ${item.type.name} ${item.name}: native playback, seek, ${source.subtitles.length} external subtitles, progress and watched state',
            );
            await player.stop();
          }
          expect(errors, isEmpty);
        } finally {
          await errorSubscription.cancel();
          await player.dispose();
          await tester.pumpWidget(const SizedBox());
        }
        // Run supplementary filtering only after all essential media checks.
        expect(
          await client.years(auth.userId, movies.id),
          contains(movie.productionYear),
        );
        expect(
          (await client.items(
            auth.userId,
            movies.id,
            types: {MediaType.movie},
            genre: genres.first,
            year: movie.productionYear,
          )).items,
          isNotEmpty,
        );
      } catch (error, stack) {
        Error.throwWithStackTrace(
          StateError(redactPlaybackError(error, secrets: [token, password])),
          stack,
        );
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
