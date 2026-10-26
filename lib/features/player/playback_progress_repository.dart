import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/settings.dart';

abstract interface class PlaybackProgressRepository {
  Future<int?> load({
    required String serverId,
    required String userId,
    required String itemId,
  });

  Future<Map<String, int>> loadAll({
    required String serverId,
    required String userId,
  });

  Future<void> save({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  });

  Future<void> clearIfMatches({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  });
}

class PreferencesPlaybackProgressRepository
    implements PlaybackProgressRepository {
  PreferencesPlaybackProgressRepository(this.preferences);

  final SharedPreferencesAsync preferences;

  @override
  Future<int?> load({
    required String serverId,
    required String userId,
    required String itemId,
  }) => preferences.getInt(_key(serverId, userId, itemId));

  @override
  Future<Map<String, int>> loadAll({
    required String serverId,
    required String userId,
  }) async {
    final prefix = _prefix(serverId, userId);
    final values = await preferences.getAll();
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix) && entry.value is int)
          Uri.decodeComponent(entry.key.substring(prefix.length)):
              entry.value! as int,
    };
  }

  @override
  Future<void> save({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  }) => preferences.setInt(_key(serverId, userId, itemId), positionTicks);

  @override
  Future<void> clearIfMatches({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  }) async {
    final key = _key(serverId, userId, itemId);
    if (await preferences.getInt(key) == positionTicks) {
      await preferences.remove(key);
    }
  }

  static String _key(String serverId, String userId, String itemId) =>
      '${_prefix(serverId, userId)}${Uri.encodeComponent(itemId)}';

  static String _prefix(String serverId, String userId) =>
      'sakuga.playback.v1.'
      '${Uri.encodeComponent(serverId)}.'
      '${Uri.encodeComponent(userId)}.';
}

final playbackProgressRepositoryProvider = Provider<PlaybackProgressRepository>(
  (ref) =>
      PreferencesPlaybackProgressRepository(ref.watch(preferencesProvider)),
);
