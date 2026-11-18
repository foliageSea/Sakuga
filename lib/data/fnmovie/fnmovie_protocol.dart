import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

// Wire compatibility with fnmovie (MIT); see docs/third-party-notices.md.
const fnMovieClientHeaders = {
  'X-Trim-Client': 'web',
  'X-Trim-Client-Version': '631',
};
const fnMovieArtworkOriginHeader = 'X-Sakuga-FnMovie-Origin';
const fnMovieArtworkProfileHeader = 'X-Sakuga-FnMovie-Profile';
const fnMoviePlaybackUserAgent = 'Sakuga';

final _random = Random.secure();

String fnMovieSignature(
  Uri uri,
  String method, {
  String body = '',
  int? nonce,
  int? timestamp,
}) {
  final query = uri.queryParametersAll;
  final keys = query.keys.toList()..sort();
  final input = method == 'GET'
      ? [
          for (final key in keys)
            for (final value in query[key]!) '$key=$value',
        ].join('&')
      : body;
  final digest = md5.convert(utf8.encode(input));
  final escapedPath = uri.path;
  final n = nonce ?? 100000 + _random.nextInt(900000);
  final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
  final message =
      'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh_${escapedPath}_'
      '${n}_${ts}_${digest}_16CCEB3D-AB42-077D-36A1-F355324E4237';
  return 'nonce=$n&timestamp=$ts&sign=${md5.convert(utf8.encode(message))}';
}

Map<String, String> fnMovieHeaders(
  Uri uri,
  String method, {
  String token = '',
  String body = '',
}) => {
  ...fnMovieClientHeaders,
  'authx': fnMovieSignature(uri, method, body: body),
  if (token.isNotEmpty) 'Authorization': token,
};

bool fnMovieHttpUri(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty;

bool fnMovieSameOrigin(Uri a, Uri b) =>
    fnMovieHttpUri(a) && fnMovieHttpUri(b) && a.origin == b.origin;

Uri fnMovieBaseUri(String value) {
  final uri = Uri.parse(value);
  if (!fnMovieHttpUri(uri) || uri.hasQuery || uri.hasFragment) {
    throw const FormatException('Invalid fnOS Media server URL');
  }
  return Uri.parse(uri.toString().replaceFirst(RegExp(r'/+$'), ''));
}

Uri fnMovieEndpoint(Uri base, String route, [Map<String, String>? query]) =>
    Uri.parse('$base/api/v1/$route').replace(queryParameters: query);

/// Preserve a reverse proxy mount for server paths such as `/api/v1/...`.
Uri? fnMovieResourceUri(Uri base, String value) {
  final reference = Uri.tryParse(value.trim());
  if (reference == null || value.trim().isEmpty) return null;
  final path = reference.path;
  final target = reference.hasAuthority || reference.hasScheme
      ? base.resolveUri(reference)
      : path.startsWith('${base.path}/') && base.path.isNotEmpty
      ? base.resolveUri(reference)
      : Uri.parse('$base/')
            .resolve(value.trim().replaceFirst(RegExp(r'^/'), ''));
  return fnMovieHttpUri(target) ? target.removeFragment() : null;
}
