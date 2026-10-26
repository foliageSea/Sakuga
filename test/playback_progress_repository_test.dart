import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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
}
