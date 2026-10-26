import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
