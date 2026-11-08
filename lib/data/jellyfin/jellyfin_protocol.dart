String jellyfinDeviceIdentity(String deviceId, String username) =>
    username.isEmpty
    ? deviceId
    : '$deviceId:${Uri.encodeComponent(username.trim().toLowerCase())}';

Map<String, String> jellyfinAuthHeaders({
  String token = '',
  String deviceId = 'sakuga',
  String username = '',
}) {
  String quote(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f"\\]'), '_');
  final identity = jellyfinDeviceIdentity(
    deviceId.isEmpty ? 'sakuga' : deviceId,
    username,
  );
  return {
    'Authorization':
        'MediaBrowser ${token.isEmpty ? '' : 'Token="${quote(token)}", '}Client="Sakuga", Device="Sakuga", DeviceId="${quote(identity)}", Version="0.1.0"',
  };
}
