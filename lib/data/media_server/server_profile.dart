enum MediaServerType { jellyfin }

class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.type = MediaServerType.jellyfin,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final MediaServerType type;

  ServerProfile copyWith({String? name, String? baseUrl, String? apiKey}) =>
      ServerProfile(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        type: type,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'type': type.name,
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
    apiKey: json['apiKey'] as String? ?? '',
    type: json['type'] == null
        ? MediaServerType.jellyfin
        : MediaServerType.values.byName(json['type'] as String),
  );
}
