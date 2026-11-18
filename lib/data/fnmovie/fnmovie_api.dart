import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/app_exception.dart';
import 'fnmovie_mapper.dart';
import 'fnmovie_protocol.dart';

Future<List<Map<String, dynamic>>> fetchFnMovieLibraries(FnMovieApi api) async {
  final data = await api.get('mdb/list');
  if (data is! List &&
      !(data is Map && const ['list', 'items', 'data'].any(data.containsKey))) {
    throw const AppException(FailureKind.invalidData);
  }
  return fnRows(data);
}

class FnMovieApi {
  FnMovieApi(String baseUrl, {this.token = '', Dio? dio})
    : _base = fnMovieBaseUri(baseUrl),
      _dio = dio ?? _sharedDio;

  static final _sharedDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  final Dio _dio;
  final String token;
  Uri _base;
  Uri get base => _base;

  Future<dynamic> get(String route, {Map<String, String>? query}) =>
      _request('GET', route, query: query);

  Future<dynamic> post(
    String route,
    Map<String, Object?> body, {
    Duration? timeout,
  }) => _request('POST', route, body: body, timeout: timeout);

  Future<dynamic> login(String username, String password) => _request(
    'POST',
    'login',
    body: {'username': username, 'password': password, 'app_name': 'Sakuga'},
    login: true,
  );

  Future<dynamic> _request(
    String method,
    String route, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool login = false,
    Duration? timeout,
  }) async {
    var uri = fnMovieEndpoint(base, route, query);
    final encoded = body == null ? '' : jsonEncode(body);
    final cancelToken = CancelToken();
    final timer = timeout == null ? null : Timer(timeout, cancelToken.cancel);
    try {
      for (var redirects = 0; redirects <= 3; redirects++) {
        final response = await _dio.requestUri<String>(
          uri,
          data: body == null ? null : encoded,
          cancelToken: cancelToken,
          options: Options(
            method: method,
            responseType: ResponseType.plain,
            contentType: Headers.jsonContentType,
            headers: {
              'Accept': 'application/json',
              ...fnMovieHeaders(uri, method, token: token, body: encoded),
            },
            followRedirects: false,
            validateStatus: (_) => true,
          ),
        );
        final status = response.statusCode;
        final location = response.headers.value('location');
        if (location != null &&
            const {301, 302, 303, 307, 308}.contains(status)) {
          final next = uri.resolve(location);
          final upgrade =
              login &&
              fnMovieHttpUri(next) &&
              uri.scheme == 'http' &&
              next.scheme == 'https' &&
              uri.host == next.host;
          final loginRedirect =
              login &&
              fnMovieHttpUri(next) &&
              uri.host == next.host &&
              (uri.scheme == next.scheme || upgrade) &&
              next.path.endsWith('/api/v1/login');
          final apiRedirect =
              !login &&
              fnMovieSameOrigin(uri, next) &&
              (method == 'GET' || status == 307 || status == 308);
          if (loginRedirect || apiRedirect) {
            uri = next.removeFragment();
            continue;
          }
        }
        if (status == 401) throw const AppException(FailureKind.auth);
        if (status == null || status < 200 || status >= 300) {
          throw AppException(FailureKind.server, status);
        }
        final decoded = response.data?.isNotEmpty == true
            ? jsonDecode(response.data!)
            : null;
        if (decoded is Map) {
          final code = int.tryParse('${decoded['code']}');
          if (code == 401) throw const AppException(FailureKind.auth);
          if (code != null && !const {0, 200, 2000}.contains(code)) {
            throw AppException(FailureKind.server, code);
          }
        }
        if (login) {
          final target = uri.toString().split('?').first;
          _base = fnMovieBaseUri(
            target.substring(0, target.length - '/api/v1/login'.length),
          );
        }
        return decoded is Map && decoded.containsKey('data')
            ? decoded['data']
            : decoded;
      }
      throw const AppException(FailureKind.server);
    } on DioException catch (error) {
      // Do not retain the request body, credentials, or URLs in exceptions.
      throw AppException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => FailureKind.timeout,
        DioExceptionType.cancel =>
          timeout == null ? FailureKind.cancelled : FailureKind.timeout,
        _ => FailureKind.network,
      });
    } on FormatException {
      throw const AppException(FailureKind.invalidData);
    } finally {
      timer?.cancel();
    }
  }
}
