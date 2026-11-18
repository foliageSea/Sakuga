import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';

import 'ugreen_transport.dart';

/// Adapts pinned HTTPS media to a capability URL on the IPv4 loopback only.
class UgreenPlaybackProxy {
  UgreenPlaybackProxy._(this.url, this._worker, this._stop, this._exited);

  final String url;
  final Isolate _worker;
  final SendPort _stop;
  final Future<void> _exited;
  Future<void>? _closing;

  static Future<UgreenPlaybackProxy> start({
    required String baseUrl,
    required String fingerprint,
    required Uri upstream,
  }) async {
    requireUgreenOrigin(Uri.parse(normalizeUgreenBaseUrl(baseUrl)), upstream);
    final ready = ReceivePort();
    final exit = ReceivePort();
    final exited = exit.first.then<void>((_) => exit.close());
    Isolate? worker;
    try {
      // libmpv performs synchronous native calls on the UI isolate. Keep the
      // HTTP server independent so those calls cannot starve its own stream.
      worker = await Isolate.spawn(
        _serveInWorker,
        (ready.sendPort, baseUrl, fingerprint, upstream.toString()),
        onError: ready.sendPort,
        onExit: exit.sendPort,
      );
      final result = await ready.first.timeout(const Duration(seconds: 10));
      if (result is! (String, SendPort)) {
        throw const SocketException('UGREEN proxy unavailable');
      }
      return UgreenPlaybackProxy._(result.$1, worker, result.$2, exited);
    } catch (_) {
      if (worker == null) {
        exit.close();
      } else {
        worker.kill(priority: Isolate.immediate);
      }
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _stop.send(null);
    try {
      await _exited.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _worker.kill(priority: Isolate.immediate);
      await _exited;
    }
  }
}

Future<void> _serveInWorker((SendPort, String, String, String) args) async {
  final (ready, baseUrl, fingerprint, upstream) = args;
  try {
    final proxy = await _PlaybackServer.start(
      baseUrl: baseUrl,
      fingerprint: fingerprint,
      upstream: Uri.parse(upstream),
    );
    final stop = ReceivePort();
    ready.send((proxy.url, stop.sendPort));
    await stop.first;
    stop.close();
    await proxy.close();
  } catch (_) {
    ready.send(null);
  }
}

class _PlaybackServer {
  _PlaybackServer._(this._server, this._client, this._base, this._upstream)
    : _path = '/${_randomPath()}' {
    _server.listen(_serve);
  }

  final HttpServer _server;
  final HttpClient _client;
  final Uri _base;
  final Uri _upstream;
  final String _path;

  static Future<_PlaybackServer> start({
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
      return _PlaybackServer._(server, client, base, upstream);
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  String get url => 'http://127.0.0.1:${_server.port}$_path';

  Future<void> close() async {
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
