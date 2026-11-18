import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'ugreen_transport.dart';

/// Adapts pinned HTTPS media to a capability URL on the IPv4 loopback only.
class UgreenPlaybackProxy {
  UgreenPlaybackProxy._(this._server, this._client, this._base, this._upstream)
    : _path = '/${_randomPath()}' {
    _server.listen(_serve);
  }

  final HttpServer _server;
  final HttpClient _client;
  final Uri _base;
  final Uri _upstream;
  final String _path;
  Future<void>? _closing;

  static Future<UgreenPlaybackProxy> start({
    required String baseUrl,
    required String fingerprint,
    required Uri upstream,
  }) async {
    final base = Uri.parse(normalizeUgreenBaseUrl(baseUrl));
    requireUgreenOrigin(base, upstream);
    final client = createUgreenHttpClient(baseUrl, fingerprint)
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      return UgreenPlaybackProxy._(server, client, base, upstream);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  String get url => 'http://127.0.0.1:${_server.port}$_path';

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _client.close(force: true);
    await _server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final destination = request.response;
    var streaming = false;
    try {
      // Require the loopback Host too: a DNS-rebinding request is not local
      // playback even if its TCP connection eventually reaches loopback.
      if (request.headers.value(HttpHeaders.hostHeader) !=
              '127.0.0.1:${_server.port}' ||
          request.uri.path != _path ||
          request.uri.hasQuery) {
        destination.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        destination.statusCode = HttpStatus.methodNotAllowed;
        destination.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        return;
      }
      destination.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      final source = await _open(request);
      destination.statusCode = source.statusCode;
      for (final name in const [
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentEncodingHeader,
        HttpHeaders.etagHeader,
        HttpHeaders.lastModifiedHeader,
      ]) {
        final values = source.headers[name];
        if (values != null) destination.headers.set(name, values);
      }
      if (source.contentLength >= 0) {
        destination.contentLength = source.contentLength;
      }
      if (request.method == 'HEAD' ||
          source.statusCode == HttpStatus.noContent ||
          source.statusCode == HttpStatus.notModified) {
        await source.drain<void>();
      } else {
        streaming = true;
        await destination.addStream(source);
      }
    } catch (_) {
      // TLS/network errors and malformed redirects may include the upstream
      // URL. Never log or return them to the player.
      if (!streaming) {
        destination.headers.clear();
        destination.statusCode = HttpStatus.badGateway;
      }
    } finally {
      try {
        await destination.close();
      } catch (_) {
        // The player can disconnect mid-range or while the proxy is closing.
      }
    }
  }

  Future<HttpClientResponse> _open(HttpRequest incoming) async {
    var target = _upstream;
    for (var redirects = 0; redirects <= 3; redirects++) {
      final request = await _client.openUrl(incoming.method, target);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      for (final name in const [
        HttpHeaders.rangeHeader,
        HttpHeaders.ifRangeHeader,
        HttpHeaders.ifNoneMatchHeader,
        HttpHeaders.ifModifiedSinceHeader,
      ]) {
        final values = incoming.headers[name];
        if (values != null) request.headers.set(name, values);
      }
      final response = await request.close();
      var keepResponse = false;
      try {
        final next = ugreenRedirectTarget(_base, target, response);
        if (next == null) {
          keepResponse = true;
          return response;
        }
        target = next;
      } finally {
        if (!keepResponse) await response.listen((_) {}).cancel();
      }
    }
    throw const FormatException('Too many Ugreen playback redirects');
  }
}

String _randomPath() {
  final random = Random.secure();
  return base64Url.encode(List.generate(24, (_) => random.nextInt(256)));
}
