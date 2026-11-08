import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../core/settings/settings.dart';
import 'emby_protocol.dart';

class EmbyAuthResult {
  const EmbyAuthResult({
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

class EmbyAuthService {
  EmbyAuthService({this.dio});
  final Dio? dio;

  Future<EmbyAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    if (username.trim().isEmpty || deviceId.isEmpty) {
      throw const AppException(FailureKind.invalidData);
    }
    final url = embyApiBaseUrl(baseUrl);
    final client =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: url,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            sendTimeout: const Duration(seconds: 10),
            followRedirects: false,
          ),
        );
    try {
      final response = await client.post<Map<String, dynamic>>(
        '$url/Users/AuthenticateByName',
        data: {'Username': username.trim(), 'Pw': password},
        options: Options(
          headers: embyAuthHeaders(deviceId: deviceId),
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
      return EmbyAuthResult(
        accessToken: token,
        userId: id,
        username: user['Name'] is String
            ? user['Name'] as String
            : username.trim(),
        remoteServerId: data?['ServerId'] as String? ?? '',
      );
    } on DioException catch (error) {
      // Do not retain the auth request/response: both contain credentials.
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

final embyAuthProvider = Provider<EmbyAuthService>((ref) => EmbyAuthService());

final embyDeviceIdProvider = FutureProvider<String>((ref) async {
  final preferences = ref.watch(preferencesProvider);
  const key = 'sakuga.emby.device.v1';
  final stored = await preferences.getString(key);
  if (stored != null && stored.isNotEmpty) return stored;
  final random = Random.secure();
  final id = List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await preferences.setString(key, id);
  return id;
});
