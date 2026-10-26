import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/images/artwork_cache.dart';
import '../data/jellyfin/jellyfin_client.dart';
import '../data/jellyfin/jellyfin_models.dart';
import 'widgets.dart';

/// A remote artwork frame: cached on disk, faded in, with a placeholder behind.
class MediaImage extends StatelessWidget {
  const MediaImage({
    required this.url,
    required this.headers,
    this.icon = FLucideIcons.film,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String? url;
  final Map<String, String> headers;
  final IconData icon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null) return MediaPlaceholder(icon: icon);
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: headers,
      cacheManager: ArtworkCacheManager.instance,
      fit: fit,
      useOldImageOnUrlChange: true,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => MediaPlaceholder(icon: icon),
      errorWidget: (_, _, _) => MediaPlaceholder(icon: icon),
    );
  }
}

class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({this.icon = FLucideIcons.film, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.theme.colors.muted,
    child: Center(
      child: Icon(icon, color: context.theme.colors.mutedForeground),
    ),
  );
}

/// Builds the [Hero] tag shared between a library poster card and the detail
/// page's poster frame.
Object posterHeroTag(String itemId) => ('library-poster', itemId);

/// Wraps a poster frame so it flies between a library card and the detail
/// page when pushing or popping the detail route.
class PosterHero extends StatelessWidget {
  const PosterHero({
    required this.tag,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final Object? tag;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tag = this.tag;
    final framed = ClipRRect(
      key: tag == null ? null : ValueKey(('poster-hero-frame', tag)),
      borderRadius: borderRadius,
      child: child,
    );
    if (tag == null) return framed;
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: _flightShuttle,
      child: framed,
    );
  }

  /// Keeps the departing hero's subtree in flight in both directions so the
  /// poster already on screen animates without flashing a placeholder.
  static Widget _flightShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) => (fromHeroContext.widget as Hero).child;
}

/// A poster card with title, optional subtitle and watch progress.
///
/// Defaults to a 2:3 poster frame; pass [aspectRatio] to use the scraped shape
/// instead, e.g. a 16:9 still for episodes.
class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({
    required this.client,
    required this.item,
    this.onTap,
    this.onPosterTap,
    this.heroTag,
    this.progress,
    this.aspectRatio,
    this.translucent = false,
    super.key,
  }) : assert(onTap != null || onPosterTap != null);

  final JellyfinClient client;
  final JellyfinItem item;
  final VoidCallback? onTap;

  /// Invoked with the resolved poster URL when tapped, so a destination route
  /// can reuse the exact cached artwork frame.
  final ValueChanged<String?>? onPosterTap;

  /// Optional [Hero] tag for shared-element transitions into a detail page.
  final Object? heroTag;

  /// Watched fraction between 0 and 1, drawn as a thin bar under the poster.
  final double? progress;

  /// Frame shape; defaults to 2:3.
  final double? aspectRatio;

  /// Whether the card surface is semi-transparent over an ambient background.
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final posterUrl = client.imageUrl(item);
    final subtitle = item.displaySubtitle;
    final watched = progress;
    return GestureDetector(
      onTap: () {
        final onPosterTap = this.onPosterTap;
        if (onPosterTap != null) {
          onPosterTap(posterUrl);
        } else {
          onTap?.call();
        }
      },
      child: Surface(
        padding: 10,
        translucent: translucent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio ?? 2 / 3,
              child: PosterHero(
                tag: heroTag,
                borderRadius: theme.style.borderRadius.md,
                child: MediaImage(url: posterUrl, headers: client.authHeaders),
              ),
            ),
            if (watched != null && watched > 0) ...[
              const SizedBox(height: 6),
              MediaProgressBar(value: watched),
            ],
            const SizedBox(height: 8),
            Text(
              item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.sm,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A thin pill-shaped progress bar indicating watched fraction (`0.0..1.0`).
class MediaProgressBar extends StatelessWidget {
  const MediaProgressBar({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final fraction = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 3,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: constraints.maxWidth * fraction,
                child: ColoredBox(color: theme.colors.primary),
              ),
              Expanded(child: ColoredBox(color: theme.colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
