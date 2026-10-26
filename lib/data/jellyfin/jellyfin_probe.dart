import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';

class ServerProbeResult {
  const ServerProbeResult({
    required this.name,
    required this.version,
    required this.id,
  });

  final String name;
  final String version;
  final String id;
}

class JellyfinProbe {
  Future<ServerProbeResult> probe(String rawUrl) async {
    final baseUrl = normalizeBaseUrl(rawUrl);
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
      ),
    );
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/System/Info/Public',
      );
      final data = response.data ?? const <String, dynamic>{};
      return ServerProbeResult(
        name: data['ServerName'] as String? ?? '',
        version: data['Version'] as String? ?? '',
        id: data['Id'] as String? ?? '',
      );
    } on DioException catch (error) {
      throw AppException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => FailureKind.timeout,
        DioExceptionType.badResponse => FailureKind.server,
        _ => FailureKind.network,
      }, error);
    } finally {
      dio.close();
    }
  }
}

String normalizeBaseUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) throw const FormatException('empty URL');
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'http://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const FormatException('invalid URL');
  }
  return value.replaceAll(RegExp(r'/+$'), '');
}

final jellyfinProbeProvider = Provider<JellyfinProbe>((ref) => JellyfinProbe());
