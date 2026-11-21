import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/settings.dart';
import '../../data/media_server/media_models.dart';

typedef SavedPlaybackProgress = ({int positionTicks, DateTime? lastPlayedAt});

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

  Future<Map<String, SavedPlaybackProgress>> loadAllEntries({
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
  }) async {
    final key = _key(serverId, userId, itemId);
    final values = await preferences.getAll(allowList: {key});
    return _decode(values[key])?.positionTicks;
  }

  @override
  Future<Map<String, int>> loadAll({
    required String serverId,
    required String userId,
  }) async {
    final entries = await loadAllEntries(serverId: serverId, userId: userId);
    return entries.map((id, entry) => MapEntry(id, entry.positionTicks));
  }

  @override
  Future<Map<String, SavedPlaybackProgress>> loadAllEntries({
    required String serverId,
    required String userId,
  }) async {
    final prefix = _prefix(serverId, userId);
    final values = await preferences.getAll();
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix))
          Uri.decodeComponent(entry.key.substring(prefix.length)): ?_decode(
            entry.value,
          ),
    };
  }

  @override
  Future<void> save({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  }) => preferences.setString(
    _key(serverId, userId, itemId),
    '$positionTicks:${DateTime.now().microsecondsSinceEpoch}',
  );

  @override
  Future<void> clearIfMatches({
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  }) async {
    final key = _key(serverId, userId, itemId);
    final values = await preferences.getAll(allowList: {key});
    if (_decode(values[key])?.positionTicks == positionTicks) {
      await preferences.remove(key);
    }
  }

  static SavedPlaybackProgress? _decode(Object? value) {
    // Older releases wrote only ticks. Keep those positions without inventing
    // a last-played date for them.
    if (value is int) return (positionTicks: value, lastPlayedAt: null);
    if (value is! String) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final ticks = int.tryParse(parts.first);
    final micros = int.tryParse(parts.last);
    if (ticks == null || micros == null) return null;
    return (
      positionTicks: ticks,
      lastPlayedAt: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
    );
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

extension PlaybackProgressOverlay on PlaybackProgressRepository {
  Future<int?> tryLoad({
    required String serverId,
    required String userId,
    required String itemId,
  }) async {
    try {
      return await load(serverId: serverId, userId: userId, itemId: itemId);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> tryLoadAll({
    required String serverId,
    required String userId,
  }) async {
    try {
      return await loadAll(serverId: serverId, userId: userId);
    } catch (_) {
      return const {};
    }
  }

  Future<Map<String, SavedPlaybackProgress>> tryLoadAllEntries({
    required String serverId,
    required String userId,
  }) async {
    try {
      return await loadAllEntries(serverId: serverId, userId: userId);
    } catch (_) {
      return const {};
    }
  }

  Future<MediaItem> overlayItem(
    MediaItem item, {
    required String serverId,
    required String userId,
  }) async {
    final ticks = await tryLoad(
      serverId: serverId,
      userId: userId,
      itemId: item.id,
    );
    return ticks == null
        ? item
        : item.withPlaybackPosition(Duration(microseconds: ticks ~/ 10));
  }

  Future<List<MediaItem>> overlayItems(
    List<MediaItem> items, {
    required String serverId,
    required String userId,
  }) async {
    if (items.isEmpty) return items;
    final pending = await tryLoadAll(serverId: serverId, userId: userId);
    if (pending.isEmpty) return items;
    return [
      for (final item in items)
        if (pending[item.id] case final ticks?)
          item.withPlaybackPosition(Duration(microseconds: ticks ~/ 10))
        else
          item,
    ];
  }
}
