import 'dart:io';
import 'dart:math';

import 'fnmovie_protocol.dart';

/// mpv never sees server credentials. Each open has a private loopback URL,
/// with a fresh signature per upstream GET or seek.
class FnMoviePlaybackProxy {
  FnMoviePlaybackProxy._(this._server, this._client, this.url);

  final HttpServer _server;
  final HttpClient _client;
  final String url;
  bool _closed = false;

  static Future<FnMoviePlaybackProxy> start({
    required Uri base,
    required Uri upstream,
    Uri? fallback,
    required String token,
  }) async {
    final random = Random.secure();
    final path =
        '/${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 10);
    Uri? committedSource;
    server.listen((request) async {
      final response = request.response;
      try {
        if (request.uri.path != path ||
            (request.method != 'GET' && request.method != 'HEAD')) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        var source = committedSource ?? upstream;
        var target = source;
        bool useFallback() {
          if (fallback == null ||
              source == fallback ||
              committedSource == upstream) {
            return false;
          }
          source = fallback;
          target = fallback;
          return true;
        }

        for (var redirects = 0; redirects <= 3; redirects++) {
          if (!fnMovieSameOrigin(base, target)) {
            if (!useFallback() || !fnMovieSameOrigin(base, target)) break;
          }
          final outgoing = await client.openUrl(request.method, target);
          outgoing.followRedirects = false;
          outgoing.headers.set(
            HttpHeaders.userAgentHeader,
            fnMoviePlaybackUserAgent,
          );
          outgoing.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          for (final name in const [
            HttpHeaders.rangeHeader,
            HttpHeaders.ifRangeHeader,
          ]) {
            final value = request.headers[name];
            if (value != null) outgoing.headers.set(name, value);
          }
          fnMovieHeaders(
            target,
            request.method,
            token: token,
          ).forEach(outgoing.headers.set);
          final incoming = await outgoing.close().timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              outgoing.abort();
              throw const HttpException('Playback request timed out');
            },
          );
          if (incoming.isRedirect) {
            final location = incoming.headers.value(HttpHeaders.locationHeader);
            await incoming.listen((_) {}).cancel();
            if (location == null) break;
            target = target.resolve(location);
            continue;
          }
          // This proxy serves a file, not a playlist with separately signed URLs.
          final mime =
              incoming.headers.contentType?.mimeType.toLowerCase() ?? '';
          final playlist =
              mime.contains('mpegurl') || mime == 'application/dash+xml';
          final directFailed =
              incoming.statusCode >= 400 ||
              playlist ||
              (request.headers[HttpHeaders.rangeHeader] != null &&
                  incoming.statusCode != HttpStatus.partialContent);
          if (directFailed && useFallback()) {
            await incoming.listen((_) {}).cancel();
            continue;
          }
          if (playlist) {
            await incoming.listen((_) {}).cancel();
            break;
          }
          // Never mix byte ranges from a direct link and the original file.
          if (request.method == 'GET' &&
              incoming.statusCode >= 200 &&
              incoming.statusCode < 300) {
            committedSource ??= source;
            if (committedSource != source) {
              await incoming.listen((_) {}).cancel();
              source = committedSource!;
              target = source;
              continue;
            }
          }
          response.statusCode = incoming.statusCode;
          for (final name in const [
            HttpHeaders.contentTypeHeader,
            HttpHeaders.contentLengthHeader,
            HttpHeaders.contentRangeHeader,
            HttpHeaders.acceptRangesHeader,
            HttpHeaders.contentEncodingHeader,
            HttpHeaders.etagHeader,
            HttpHeaders.lastModifiedHeader,
          ]) {
            final value = incoming.headers[name];
            if (value != null) response.headers.set(name, value);
          }
          await response.addStream(incoming);
          return;
        }
        response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        try {
          response.statusCode = HttpStatus.badGateway;
        } on StateError {
          // A seek or disposal can close a response already streaming.
        } on HttpException {
          // Headers already sent.
        }
      } finally {
        try {
          await response.close();
        } catch (_) {
          // The player may have already disconnected.
        }
      }
    });
    return FnMoviePlaybackProxy._(
      server,
      client,
      'http://127.0.0.1:${server.port}$path',
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await _server.close(force: true);
  }
}
