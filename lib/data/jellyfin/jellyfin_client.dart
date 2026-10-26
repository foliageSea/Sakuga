import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import 'jellyfin_models.dart';
import 'server_profile.dart';

class JellyfinClient {
  JellyfinClient({required this.server, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: server.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 10),
              headers: _headers(server.apiKey),
            ),
          );

  final ServerProfile server;
  final Dio _dio;

  Map<String, String> get authHeaders => _headers(server.apiKey);

  static Map<String, String> _headers(String apiKey) => {
    'Authorization':
        'MediaBrowser Token="$apiKey", Client="Sakuga", Device="Sakuga", DeviceId="sakuga", Version="0.1.0"',
  };

  Future<List<JellyfinUser>> users() async {
    if (server.apiKey.isEmpty) {
      throw const AppException(FailureKind.auth);
    }
    final response = await _dio.get<List<dynamic>>('/Users');
    return (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(JellyfinUser.fromJson)
        .where((user) => user.id.isNotEmpty)
        .toList();
  }

  Future<List<JellyfinView>> views(String userId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/UserViews',
        queryParameters: {'userId': userId},
      );
      return _parseViews(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final response = await _dio.get<Map<String, dynamic>>(
        '/Users/$userId/Views',
      );
      return _parseViews(response.data);
    }
  }

  Future<List<JellyfinItem>> items(
    String userId,
    String parentId, {
    int limit = 60,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/Items',
      queryParameters: {
        'userId': userId,
        'parentId': parentId,
        'recursive': true,
        'includeItemTypes': 'Movie,Series,Episode,Video,MusicVideo',
        'sortBy': 'SortName',
        'sortOrder': 'Ascending',
        'fields': 'PrimaryImageAspectRatio,ImageTags,UserData',
        'imageTypeLimit': 1,
        'limit': limit,
      },
    );
    final items = response.data?['Items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(JellyfinItem.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  List<JellyfinView> _parseViews(Map<String, dynamic>? data) {
    final items = data?['Items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(JellyfinView.fromJson)
        .where((view) => view.id.isNotEmpty)
        .toList();
  }

  String? imageUrl(JellyfinItem item, {int width = 400}) {
    final tag = item.imageTags['Primary'];
    if (tag == null || tag.isEmpty) return null;
    return '${server.baseUrl}/Items/${item.id}/Images/Primary?maxWidth=$width&tag=$tag';
  }
}
