import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings.dart';
import '../media_browser/media_browser_auth.dart';
import 'emby_protocol.dart';

typedef EmbyAuthResult = MediaBrowserAuthResult;

class EmbyAuthService extends MediaBrowserAuthService {
  EmbyAuthService({super.dio});
  @override
  String authBaseUrl(String baseUrl) => embyApiBaseUrl(baseUrl);
  @override
  Map<String, String> authHeaders(String deviceId, String username) =>
      embyAuthHeaders(deviceId: deviceId);
}

final embyAuthProvider = Provider<EmbyAuthService>((ref) => EmbyAuthService());
final embyDeviceIdProvider = FutureProvider<String>(
  (ref) => loadOrCreateDeviceId(
    ref.watch(preferencesProvider),
    'sakuga.emby.device.v1',
  ),
);
