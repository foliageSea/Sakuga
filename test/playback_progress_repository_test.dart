import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/features/player/playback_progress_repository.dart';

void main() {
  late SharedPreferencesAsyncPlatform? original;

  setUp(() {
    original = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = original);

  test('stores pending progress per server, user and item', () async {
    final repository = PreferencesPlaybackProgressRepository(
      SharedPreferencesAsync(),
    );

    await repository.save(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'episode-1',
      positionTicks: 123000000,
    );

    expect(
      await repository.load(
        serverId: 'server-1',
        userId: 'user-1',
        itemId: 'episode-1',
      ),
      123000000,
    );
    expect(
      await repository.load(
        serverId: 'server-2',
        userId: 'user-1',
        itemId: 'episode-1',
      ),
      isNull,
    );
    expect(await repository.loadAll(serverId: 'server-1', userId: 'user-1'), {
      'episode-1': 123000000,
    });
  });

  test('clears matching pending progress after a successful sync', () async {
    final repository = PreferencesPlaybackProgressRepository(
      SharedPreferencesAsync(),
    );
    await repository.save(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'episode-1',
      positionTicks: 123000000,
    );

    await repository.clearIfMatches(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'episode-1',
      positionTicks: 123000000,
    );

    expect(
      await repository.load(
        serverId: 'server-1',
        userId: 'user-1',
        itemId: 'episode-1',
      ),
      isNull,
    );
  });

  test('keeps newer pending progress after an older sync succeeds', () async {
    final repository = PreferencesPlaybackProgressRepository(
      SharedPreferencesAsync(),
    );
    await repository.save(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'episode-1',
      positionTicks: 456000000,
    );

    await repository.clearIfMatches(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'episode-1',
      positionTicks: 123000000,
    );

    expect(
      await repository.load(
        serverId: 'server-1',
        userId: 'user-1',
        itemId: 'episode-1',
      ),
      456000000,
    );
  });

  test('overlays pending partial and completed progress onto items', () async {
    final repository = PreferencesPlaybackProgressRepository(
      SharedPreferencesAsync(),
    );
    await repository.save(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'ep-partial',
      positionTicks: 300000000,
    );
    await repository.save(
      serverId: 'server-1',
      userId: 'user-1',
      itemId: 'ep-done',
      positionTicks: 0,
    );

    final overlaid = await repository.overlayItems(
      const [
        MediaItem(
          id: 'ep-partial',
          name: 'Ep 1',
          type: MediaType.episode,
          runtime: Duration(seconds: 60),
        ),
        MediaItem(
          id: 'ep-done',
          name: 'Ep 2',
          type: MediaType.episode,
          runtime: Duration(seconds: 60),
          playbackPosition: Duration(seconds: 50),
          reportedPlayedPercentage: 83.3,
        ),
      ],
      serverId: 'server-1',
      userId: 'user-1',
    );

    expect(overlaid[0].playbackPosition, const Duration(seconds: 30));
    expect(overlaid[0].progressFraction, closeTo(0.5, 0.001));
    expect(overlaid[0].played, isFalse);

    expect(overlaid[1].playbackPosition, Duration.zero);
    expect(overlaid[1].progressFraction, isNull);
    expect(overlaid[1].played, isTrue);
  });
}
