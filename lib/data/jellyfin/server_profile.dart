class ServerProfile {
  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
  });

  final String id;
  final String name;
  final String baseUrl;

  ServerProfile copyWith({String? name, String? baseUrl}) => ServerProfile(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
  );

  Map<String, Object> toJson() => {'id': id, 'name': name, 'baseUrl': baseUrl};

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
  );
}
