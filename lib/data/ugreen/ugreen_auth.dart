import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../core/settings/settings.dart';
import '../media_browser/media_browser_auth.dart';
import 'ugreen_transport.dart';

class UgreenAuthService {
  UgreenAuthService({this.dio});

  final Dio? dio;

  Future<MediaBrowserAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
    String fingerprint = '',
  }) async {
    final name = username.trim();
    if (name.isEmpty || deviceId.trim().isEmpty) {
      throw const AppException(FailureKind.invalidData);
    }
    final base = normalizeUgreenBaseUrl(baseUrl);
    final pin = normalizeUgreenFingerprint(fingerprint);
    final client = dio ?? createUgreenDio(base, pin);
    try {
      final response = await client.post<Object?>(
        '${ugreenApiBaseUrl(base)}/Users/AuthenticateByName',
        data: {'Username': name, 'Pw': password},
        options: ugreenJsonOptions(deviceId: deviceId),
      );
      final data = response.data;
      if (data is! Map) throw const AppException(FailureKind.invalidData);
      final user = data['User'];
      final userId =
          (user is Map ? ugreenId(user['Id']) : null) ??
          ugreenId(data['UserId']) ??
          ugreenId(data['UserID']);
      final token = data['AccessToken'];
      if (token is! String || token.trim().isEmpty || userId == null) {
        throw const AppException(FailureKind.invalidData);
      }
      final returnedName = user is Map ? user['Name'] : null;
      return MediaBrowserAuthResult(
        accessToken: token.trim(),
        userId: userId,
        username: returnedName is String && returnedName.trim().isNotEmpty
            ? returnedName
            : name,
        remoteServerId: ugreenId(data['ServerId']) ?? '',
      );
    } on DioException catch (error) {
      throw ugreenRequestFailure(error);
    } finally {
      if (dio == null) client.close();
    }
  }
}

final ugreenAuthProvider = Provider<UgreenAuthService>(
  (ref) => UgreenAuthService(),
);
final ugreenDeviceIdProvider = FutureProvider<String>(
  (ref) => loadOrCreateDeviceId(
    ref.watch(preferencesProvider),
    'sakuga.ugreen.device.v1',
  ),
);

// The public media service is mounted under /emby at the normalized origin.
String ugreenApiBaseUrl(String baseUrl) => '${Uri.parse(baseUrl).origin}/emby';

String? ugreenId(Object? value) => switch (value) {
  String() when value.trim().isNotEmpty => value.trim(),
  int() => value.toString(),
  _ => null,
};

Map<String, String> ugreenMediaAuthHeaders({
  required String deviceId,
  String token = '',
}) {
  String quote(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f"\\]'), '_');
  return {
    'X-Emby-Authorization':
        'MediaBrowser Client="Sakuga", Device="Sakuga", '
        'DeviceId="${quote(deviceId)}", Version="0.1.0"'
        '${token.isEmpty ? '' : ', Token="${quote(token)}"'}',
  };
}

Options ugreenJsonOptions({required String deviceId, String token = ''}) =>
    Options(
      headers: {
        ...ugreenMediaAuthHeaders(deviceId: deviceId, token: token),
        'Accept': 'application/json',
      },
      followRedirects: false,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    );

AppException ugreenRequestFailure(DioException error) {
  // Dio's request and response can contain credentials. Never expose them.
  if (error.type == DioExceptionType.badCertificate ||
      error.error is TlsException) {
    return const AppException(
      FailureKind.network,
      HandshakeException('UGREEN certificate validation failed'),
    );
  }
  final status = error.response?.statusCode;
  final kind = switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => FailureKind.timeout,
    DioExceptionType.badResponse when status == 401 || status == 403 =>
      FailureKind.auth,
    DioExceptionType.badResponse => FailureKind.server,
    DioExceptionType.cancel => FailureKind.cancelled,
    _ when error.error is FormatException => FailureKind.invalidData,
    _ => FailureKind.network,
  };
  return AppException(kind, status);
}
