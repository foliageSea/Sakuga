import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_exception.dart';
import '../logging.dart';

enum NetworkScenario { success, empty, timeout, server }

const useMockApi = bool.fromEnvironment('USE_MOCK_API', defaultValue: true);
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

Dio createDio({bool mock = useMockApi, String baseUrl = apiBaseUrl}) {
  final uri = Uri.tryParse(baseUrl);
  if (!mock &&
      (uri == null ||
          !uri.hasAuthority ||
          !['http', 'https'].contains(uri.scheme))) {
    throw const AppException(
      FailureKind.invalidData,
      'API_BASE_URL is required',
    );
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: mock ? 'https://demo.invalid' : baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  if (mock) dio.httpClientAdapter = DemoAdapter();
  dio.interceptors.add(_ApiLoggingInterceptor());
  return dio;
}

class _ApiLoggingInterceptor extends Interceptor with LoggingMixin {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Log only method: URLs, headers, query and bodies may contain secrets.
    if (kDebugMode) log.fine('HTTP ${options.method}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) log.fine('HTTP ${response.statusCode}');
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      log.warning(
        'HTTP ${error.type.name} ${error.response?.statusCode ?? ''}',
      );
    }
    handler.next(error);
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = createDio();
  ref.onDispose(() => dio.close(force: true));
  return dio;
});
AppException mapNetworkError(Object e) => e is AppException
    ? e
    : AppException(switch (e) {
        DioException(type: DioExceptionType.cancel) => FailureKind.cancelled,
        DioException(
          type: DioExceptionType.connectionTimeout ||
              DioExceptionType.sendTimeout ||
              DioExceptionType.receiveTimeout,
        ) =>
          FailureKind.timeout,
        DioException(type: DioExceptionType.badResponse) => FailureKind.server,
        FormatException() || TypeError() => FailureKind.invalidData,
        _ => FailureKind.network,
      }, e);

class DemoAdapter implements HttpClientAdapter {
  bool _closed = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future.any([
      Future<void>.delayed(const Duration(milliseconds: 450)),
      if (cancelFuture != null)
        cancelFuture.then(
          (_) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        ),
    ]);
    if (_closed) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    }
    final scenario =
        options.extra['scenario'] as NetworkScenario? ??
        NetworkScenario.success;
    if (scenario == NetworkScenario.timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    final body = scenario == NetworkScenario.empty
        ? <Object>[]
        : [
            {'id': 1, 'title': 'Forui'},
            {'id': 2, 'title': 'Riverpod'},
            {'id': 3, 'title': 'Flutter'},
          ];
    return ResponseBody.fromString(
      jsonEncode(body),
      scenario == NetworkScenario.server ? 500 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) => _closed = true;
}

final networkItemsProvider = FutureProvider.autoDispose
    .family<List<String>, NetworkScenario>((ref, scenario) async {
      final cancel = CancelToken();
      ref.onDispose(() => cancel.cancel());
      try {
        final response = await ref
            .watch(dioProvider)
            .get<Object>(
              '/items',
              cancelToken: cancel,
              options: Options(extra: {'scenario': scenario}),
            );
        return (response.data as List)
            .map((v) => (v as Map<String, dynamic>)['title'] as String)
            .toList();
      } catch (e) {
        throw mapNetworkError(e);
      }
    });
