import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import '../media_server/server_probe.dart';
import 'emby_protocol.dart';

class EmbyProbe implements ServerProbe {
  EmbyProbe({this.dio});
  final Dio? dio;

  @override
  Future<ServerProbeResult> probe(String rawUrl, {String apiKey = ''}) async {
    final client = dio ?? Dio();
    client.options = client.options.copyWith(
      baseUrl: embyApiBaseUrl(rawUrl),
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      followRedirects: false,
      headers: embyAuthHeaders(
        accessToken: apiKey.trim(),
        deviceId: 'sakuga-probe',
      ),
    );
    try {
      final response = await client.get<Map<String, dynamic>>(
        apiKey.trim().isEmpty ? '/System/Info/Public' : '/System/Info',
      );
      final data = response.data ?? const <String, dynamic>{};
      return ServerProbeResult(
        name: data['ServerName'] as String? ?? '',
        version: data['Version'] as String? ?? '',
        id: data['Id'] as String? ?? '',
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw AppException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => FailureKind.timeout,
        DioExceptionType.badResponse when status == 401 || status == 403 =>
          FailureKind.auth,
        DioExceptionType.badResponse => FailureKind.server,
        _ => FailureKind.network,
      }, error);
    } finally {
      if (dio == null) client.close();
    }
  }
}
