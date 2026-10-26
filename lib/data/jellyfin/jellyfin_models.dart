class JellyfinUser {
  const JellyfinUser({required this.id, required this.name});

  final String id;
  final String name;

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
  );
}

class JellyfinView {
  const JellyfinView({
    required this.id,
    required this.name,
    required this.collectionType,
  });

  final String id;
  final String name;
  final String? collectionType;

  factory JellyfinView.fromJson(Map<String, dynamic> json) => JellyfinView(
    id: json['Id'] as String? ?? '',
    name: json['Name'] as String? ?? '',
    collectionType: json['CollectionType'] as String?,
  );
}

class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    required this.type,
    required this.imageTags,
    this.seriesId,
    this.indexNumber,
    this.userData,
  });

  final String id;
  final String name;
  final String type;
  final Map<String, String> imageTags;
  final String? seriesId;
  final int? indexNumber;
  final Map<String, dynamic>? userData;

  bool get played => userData?['Played'] == true;

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    final tags = json['ImageTags'];
    return JellyfinItem(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String? ?? '',
      imageTags: tags is Map
          ? tags.map((key, value) => MapEntry(key.toString(), value.toString()))
          : const {},
      seriesId: json['SeriesId'] as String?,
      indexNumber: json['IndexNumber'] as int?,
      userData: json['UserData'] is Map<String, dynamic>
          ? json['UserData'] as Map<String, dynamic>
          : null,
    );
  }
}
