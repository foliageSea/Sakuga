enum MediaServerType { jellyfin, emby, fnmovie }

extension MediaServerCapabilities on MediaServerType {
  bool get supportsPlaybackQuality => this != MediaServerType.fnmovie;
  bool get supportsManualPlayed => this != MediaServerType.fnmovie;
  bool get supportsLibraryOptions => this != MediaServerType.fnmovie;
  bool get supportsRecentlyAdded => this != MediaServerType.fnmovie;
}

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.type = MediaServerType.jellyfin,
    this.accessToken = '',
    this.userId = '',
    this.username = '',
    this.deviceId = '',
    this.remoteServerId = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final MediaServerType type;

  final String accessToken;
  final String userId;
  final String username;
  final String deviceId;
  final String remoteServerId;

  bool get usesAccount =>
      type != MediaServerType.jellyfin ||
      accessToken.isNotEmpty ||
      userId.isNotEmpty ||
      username.isNotEmpty;

  ServerProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    MediaServerType? type,
    String? accessToken,
    String? userId,
    String? username,
    String? deviceId,
    String? remoteServerId,
  }) => ServerProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    type: type ?? this.type,
    accessToken: accessToken ?? this.accessToken,
    userId: userId ?? this.userId,
    username: username ?? this.username,
    deviceId: deviceId ?? this.deviceId,
    remoteServerId: remoteServerId ?? this.remoteServerId,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': usesAccount ? '' : apiKey,
    'type': type.name,
    if (usesAccount) ...{
      'accessToken': accessToken,
      'userId': userId,
      'username': username,
      'deviceId': deviceId,
      'remoteServerId': remoteServerId,
    },
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
    type: json['type'] == null
        ? MediaServerType.jellyfin
        : MediaServerType.values.byName(json['type'] as String),
    accessToken: json['accessToken'] as String? ?? '',
    userId: json['userId'] as String? ?? '',
    username: json['username'] as String? ?? '',
    deviceId: json['deviceId'] as String? ?? '',
    remoteServerId: json['remoteServerId'] as String? ?? '',
  );
}
