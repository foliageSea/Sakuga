import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
        ),
      );

  static const key = 'sakugaArtwork';

  static final ArtworkCacheManager instance = ArtworkCacheManager._();
}
