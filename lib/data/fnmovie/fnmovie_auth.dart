import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import 'fnmovie_api.dart';
import 'fnmovie_mapper.dart';

typedef FnMovieAuthResult = ({String accessToken, String baseUrl});

class FnMovieAuthService {
  FnMovieAuthService({this.dio});

  final Dio? dio;

  Future<FnMovieAuthResult> authenticate({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    final FnMovieApi api;
    try {
      api = FnMovieApi(baseUrl, dio: dio);
    } on FormatException {
      throw const AppException(FailureKind.invalidData);
    }
    final response = fnObject(await api.login(username, password));
    final token = fnText(response, const [
      'token',
      'access_token',
      'accessToken',
      'auth_token',
      'authToken',
    ]);
    if (token == null) throw const AppException(FailureKind.invalidData);
    final base = api.base.toString();
    await fetchFnMovieLibraries(FnMovieApi(base, token: token, dio: dio));
    return (accessToken: token, baseUrl: base);
  }
}

final fnMovieAuthProvider = Provider<FnMovieAuthService>(
  (ref) => FnMovieAuthService(),
);
