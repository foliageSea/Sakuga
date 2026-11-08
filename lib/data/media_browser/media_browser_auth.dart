import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_exception.dart';

class MediaBrowserAuthResult {
  const MediaBrowserAuthResult({
    required this.accessToken,
    required this.userId,
    required this.username,
    required this.remoteServerId,
  });
  final String accessToken;
  final String userId;
  final String username;
  final String remoteServerId;
}

abstract class MediaBrowserAuthService {
  MediaBrowserAuthService({this.dio});
  final Dio? dio;
  String authBaseUrl(String baseUrl);
  Map<String, String> authHeaders(String deviceId, String username);

  Future<MediaBrowserAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final name = username.trim();
    if (name.isEmpty || deviceId.isEmpty) {
      throw const AppException(FailureKind.invalidData);
    }
    final url = authBaseUrl(baseUrl);
    final client =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 10),
            followRedirects: false,
          ),
        );
    try {
      final response = await client.post<Map<String, dynamic>>(
        '$url/Users/AuthenticateByName',
        data: {'Username': name, 'Pw': password},
        options: Options(
          headers: authHeaders(deviceId, name),
          followRedirects: false,
        ),
      );
      final data = response.data;
      final user = data?['User'];
      final token = data?['AccessToken'];
      final id = user is Map ? user['Id'] : null;
      if (token is! String || token.isEmpty || id is! String || id.isEmpty) {
        throw const AppException(FailureKind.invalidData);
      }
      return MediaBrowserAuthResult(
        accessToken: token,
        userId: id,
        username: user['Name'] is String ? user['Name'] as String : name,
        remoteServerId: data?['ServerId'] as String? ?? '',
      );
    } on DioException catch (error) {
      // Authentication bodies contain both passwords and tokens; discard them.
      if (error.response?.statusCode == 403) {
        throw const AppException(FailureKind.server, 403);
      }
      throw AppException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => FailureKind.timeout,
        DioExceptionType.badResponse when error.response?.statusCode == 401 =>
          FailureKind.auth,
        DioExceptionType.badResponse => FailureKind.server,
        DioExceptionType.cancel => FailureKind.cancelled,
        _ => FailureKind.network,
      });
    } on TypeError {
      throw const AppException(FailureKind.invalidData);
    } finally {
      if (dio == null) client.close();
    }
  }
}

Future<String> loadOrCreateDeviceId(
  SharedPreferencesAsync preferences,
  String key,
) async {
  final stored = await preferences.getString(key);
  if (stored != null && stored.isNotEmpty) return stored;
  final random = Random.secure();
  final id = List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await preferences.setString(key, id);
  return id;
}
