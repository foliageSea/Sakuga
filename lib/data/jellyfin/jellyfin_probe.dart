import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import '../media_server/server_probe.dart';

class JellyfinProbe implements ServerProbe {
  @override
  Future<ServerProbeResult> probe(String rawUrl, {String apiKey = ''}) async {
    final baseUrl = normalizeBaseUrl(rawUrl);
    final key = apiKey.trim();
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        headers: key.isEmpty
            ? null
            : {
                'Authorization':
                    'MediaBrowser Token="$key", Client="Sakuga", Device="Sakuga", DeviceId="sakuga-probe", Version="0.1.0"',
              },
      ),
    );
    try {
      final response = await dio.get<Map<String, dynamic>>(
        key.isEmpty ? '/System/Info/Public' : '/System/Info',
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
      dio.close();
    }
  }
}
