import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../../data/fnmovie/fnmovie_protocol.dart';
import '../../data/ugreen/ugreen_transport.dart';

/// Sizes the in-memory decoded [ImageCache] so several pages of posters stay
/// resident across scrolling and responsive column reflows without re-decoding
/// from disk.
void configureArtworkImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  const targetBytes = 256 << 20; // 256 MiB
  if (cache.maximumSizeBytes < targetBytes) {
    cache.maximumSizeBytes = targetBytes;
  }
}

/// Disk cache for remote artwork.
///
/// Posters and backdrops are immutable for a given URL (the URL carries the
/// server-side image tag), so caching by URL is safe: a rescrape changes the
/// tag and therefore the URL.
class ArtworkCacheManager extends CacheManager {
  ArtworkCacheManager._()
    : super(
        Config(
          key,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 2000,
          fileService: ArtworkFileService(),
        ),
      );

  static const key = 'sakugaArtwork';

  static final ArtworkCacheManager instance = ArtworkCacheManager._();
}

String? artworkCacheKey(String url, Map<String, String> headers) {
  final ugreenProfile = headers[ugreenArtworkProfileHeader];
  if (ugreenProfile != null) {
    return 'ugreen:${jsonEncode([ugreenProfile, headers[ugreenArtworkOriginHeader], headers[ugreenArtworkFingerprintHeader], url])}';
  }
  final profile = headers[fnMovieArtworkProfileHeader];
  return profile == null ? null : 'fnmovie:$profile:$url';
}

/// Sign when the file cache performs a network request, including revalidation.
/// Routing metadata is local-only and never transmitted to an artwork host.
class ArtworkFileService extends FileService {
  ArtworkFileService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final values = Map<String, String>.of(headers ?? const {});
    final ugreenOrigin = values.remove(ugreenArtworkOriginHeader);
    final ugreenPin = values.remove(ugreenArtworkFingerprintHeader);
    final ugreenProfile = values.remove(ugreenArtworkProfileHeader);
    final ugreenToken = values.remove(ugreenArtworkTokenHeader);
    if (ugreenOrigin != null ||
        ugreenPin != null ||
        ugreenProfile != null ||
        ugreenToken != null) {
      if (ugreenOrigin == null ||
          ugreenPin == null ||
          ugreenProfile == null ||
          ugreenToken == null) {
        throw const FormatException('Incomplete Ugreen artwork metadata');
      }
      return _getUgreen(url, ugreenOrigin, ugreenPin, ugreenToken, values);
    }
    values.remove(fnMovieArtworkProfileHeader);
    final origin = values.remove(fnMovieArtworkOriginHeader);
    var uri = Uri.parse(url);
    if (origin == null) {
      return HttpGetResponse(
        await _client.send(http.Request('GET', uri)..headers.addAll(values)),
      );
    }
    final base = Uri.parse(origin);
    final token = values.remove('Authorization') ?? '';
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!fnMovieSameOrigin(base, uri)) break;
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          ...values,
          ...fnMovieHeaders(uri, 'GET', token: token),
        });
      final response = await _client.send(request);
      final location = response.headers['location'];
      if (!response.isRedirect || location == null) {
        return HttpGetResponse(response);
      }
      await response.stream.listen((_) {}).cancel();
      uri = uri.resolve(location);
    }
    throw const FormatException('Invalid fnOS Media artwork redirect');
  }

  Future<FileServiceResponse> _getUgreen(
    String url,
    String origin,
    String pin,
    String token,
    Map<String, String> values,
  ) async {
    final base = Uri.parse(normalizeUgreenBaseUrl(origin));
    final client = createUgreenHttpClient(origin, pin)
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      var uri = Uri.parse(url);
      for (var redirects = 0; redirects <= 3; redirects++) {
        requireUgreenOrigin(base, uri);
        final query = Map<String, List<String>>.of(uri.queryParametersAll)
          ..remove('api_key');
        final target = uri.replace(
          queryParameters: {...query, if (token.isNotEmpty) 'api_key': token},
        );
        final request = await client.getUrl(target);
        request.followRedirects = false;
        for (final name in const [
          HttpHeaders.ifNoneMatchHeader,
          HttpHeaders.ifModifiedSinceHeader,
        ]) {
          for (final entry in values.entries) {
            if (entry.key.toLowerCase() == name) {
              request.headers.set(name, entry.value);
            }
          }
        }
        final response = await request.close();
        final next = ugreenRedirectTarget(base, uri, response);
        if (next != null) {
          await response.listen((_) {}).cancel();
          uri = next;
          continue;
        }
        final responseHeaders = <String, String>{};
        response.headers.forEach((name, values) {
          responseHeaders[name] = values.join(', ');
        });
        // CacheManager only consumes the response stream for new files.
        final hasFile =
            response.statusCode == HttpStatus.ok ||
            response.statusCode == HttpStatus.accepted;
        if (!hasFile) client.close(force: true);
        return HttpGetResponse(
          http.StreamedResponse(
            hasFile ? _ugreenContent(response, client) : const Stream.empty(),
            response.statusCode,
            contentLength:
                response.contentLength < 0 ||
                    response.compressionState ==
                        HttpClientResponseCompressionState.decompressed
                ? null
                : response.contentLength,
            headers: responseHeaders,
          ),
        );
      }
      throw const FormatException('Too many Ugreen artwork redirects');
    } catch (_) {
      client.close(force: true);
      // A dart:io error can contain the signed URL. Do not expose it.
      throw const HttpException('Ugreen artwork request failed');
    }
  }
}

Stream<List<int>> _ugreenContent(
  HttpClientResponse response,
  HttpClient client,
) async* {
  try {
    yield* response;
  } catch (_) {
    throw const HttpException('Ugreen artwork response failed');
  } finally {
    client.close(force: true);
  }
}
