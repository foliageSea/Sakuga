import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings/settings.dart';
import 'server_profile.dart';

abstract interface class ServerRepository {
  Future<List<ServerProfile>> load();
  Future<void> save(List<ServerProfile> servers);
}

class PreferencesServerRepository implements ServerRepository {
  PreferencesServerRepository(this.preferences);

  final SharedPreferencesAsync preferences;
  static const key = 'sakuga.servers.v1';

  @override
  Future<List<ServerProfile>> load() async {
    final raw = await preferences.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ServerProfile.fromJson)
        .where((server) => server.id.isNotEmpty && server.baseUrl.isNotEmpty)
        .toList();
  }

  @override
  Future<void> save(List<ServerProfile> servers) async {
    await preferences.setString(
      key,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
  }
}

final serverRepositoryProvider = Provider<ServerRepository>(
  (ref) => PreferencesServerRepository(ref.watch(preferencesProvider)),
);

final serversProvider =
    AsyncNotifierProvider<ServersNotifier, List<ServerProfile>>(
      ServersNotifier.new,
    );

class ServersNotifier extends AsyncNotifier<List<ServerProfile>> {
  static const _devUrl = String.fromEnvironment('DEV_SERVER_URL');
  static const _devApiKey = String.fromEnvironment('DEV_SERVER_API_KEY');

  @override
  Future<List<ServerProfile>> build() async {
    final stored = await ref.watch(serverRepositoryProvider).load();
    if (stored.isEmpty && _devUrl.isNotEmpty) {
      return [
        ServerProfile(
          id: 'dev',
          name: 'Dev',
          baseUrl: _devUrl,
          apiKey: _devApiKey,
        ),
      ];
    }
    return stored;
  }

  Future<void> add(ServerProfile server) async {
    final current = state.value ?? await future;
    await _save([...current, server]);
  }

  Future<void> upsert(ServerProfile server) async {
    final current = state.value ?? await future;
    await _save([
      for (final item in current)
        if (item.id == server.id) server else item,
    ]);
  }

  /// The first saved profile is the active server used by all media providers.
  Future<void> setActive(String id) async {
    final current = state.value ?? await future;
    final index = current.indexWhere((server) => server.id == id);
    if (index <= 0) return;
    await _save([
      current[index],
      ...current.where((server) => server.id != id),
    ]);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? await future;
    await _save(current.where((server) => server.id != id).toList());
  }

  Future<void> _save(List<ServerProfile> servers) async {
    await ref.read(serverRepositoryProvider).save(servers);
    state = AsyncData(servers);
  }
}
