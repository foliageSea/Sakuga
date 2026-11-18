import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import '../../data/fnmovie/fnmovie_protocol.dart';

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
}
