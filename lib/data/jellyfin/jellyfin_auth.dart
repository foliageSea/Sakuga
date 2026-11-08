import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../media_browser/media_browser_auth.dart';
import '../media_server/server_probe.dart';
import 'jellyfin_protocol.dart';

typedef JellyfinAuthResult = MediaBrowserAuthResult;

class JellyfinAuthService extends MediaBrowserAuthService {
  JellyfinAuthService({super.dio});
  @override
  String authBaseUrl(String baseUrl) => normalizeBaseUrl(baseUrl);
  @override
  Map<String, String> authHeaders(String deviceId, String username) =>
      jellyfinAuthHeaders(deviceId: deviceId, username: username);
}

final jellyfinAuthProvider = Provider<JellyfinAuthService>(
  (ref) => JellyfinAuthService(),
);
final jellyfinDeviceIdProvider = FutureProvider<String>(
  (ref) => loadOrCreateDeviceId(
    ref.watch(preferencesProvider),
    'sakuga.jellyfin.device.v1',
  ),
);
