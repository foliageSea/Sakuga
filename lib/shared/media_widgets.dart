import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/images/artwork_cache.dart';
import '../data/media_server/media_server_client.dart';
import '../data/media_server/media_models.dart';
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
class MediaPosterCard extends StatefulWidget {
  const MediaPosterCard({
    required this.client,
    required this.item,
    this.onTap,
    this.onPosterTap,
    this.heroTag,
    this.progress,
    this.subtitle,
    this.aspectRatio,
    this.translucent = true,
    this.framed = true,
    this.textAlign = TextAlign.start,
    this.showRating = false,
    this.reserveMetadataSpace = false,
    this.posterAction,
    super.key,
  }) : assert(onTap != null || onPosterTap != null);

  final MediaServerClient client;
  final MediaItem item;
  final VoidCallback? onTap;

  /// Invoked with the resolved poster URL when tapped, so a destination route
  /// can reuse the exact cached artwork frame.
  final ValueChanged<String?>? onPosterTap;

  /// Optional [Hero] tag for shared-element transitions into a detail page.
  final Object? heroTag;

  /// Watched fraction between 0 and 1, drawn as a thin bar under the poster.
  final double? progress;

  /// Optional subtitle replacing the item’s default display subtitle.
  final String? subtitle;

  /// Frame shape; defaults to 2:3.
  final double? aspectRatio;

  /// Reserve progress and subtitle rows so grid cards have equal heights.
  final bool reserveMetadataSpace;

  /// Whether the card surface is semi-transparent over an ambient background.
  final bool translucent;

  /// Whether to include the card surface, border and outer padding.
  final bool framed;

  /// Alignment of the title and subtitle below the poster.
  final TextAlign textAlign;

  /// Whether to overlay a valid community rating on the poster.
  final bool showRating;

  /// An optional action inside the bottom-right corner of the artwork.
  final Widget? posterAction;

  @override
  State<MediaPosterCard> createState() => _MediaPosterCardState();
}

class _MediaPosterCardState extends State<MediaPosterCard> {
  bool _hovered = false;
  Offset _pointerPosition = Offset.zero;

  void _updateHover(Offset localPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
    final position = Offset(
      (localPosition.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
      (localPosition.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
    );
    if (_hovered && position == _pointerPosition) return;
    setState(() {
      _hovered = true;
      _pointerPosition = position;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final posterUrl = widget.item.poster?.url();
    final subtitle = widget.subtitle ?? widget.item.displaySubtitle;
    final watched = widget.progress;
    final rating = widget.item.communityRating;
    final ratingLabel =
        widget.showRating && rating != null && rating.isFinite && rating > 0
        ? rating.toStringAsFixed(1)
        : null;
    final image = MediaImage(
      url: posterUrl,
      headers: widget.item.poster?.headers ?? const {},
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => _updateHover(event.localPosition),
      onHover: (event) => _updateHover(event.localPosition),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _hovered ? 1 : 0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, hoverProgress, _) => TweenAnimationBuilder<Offset>(
          tween: Tween(
            begin: Offset.zero,
            end: _hovered && !reduceMotion ? _pointerPosition : Offset.zero,
          ),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (context, tilt, child) {
            final lift = reduceMotion ? 0.0 : hoverProgress;
            final scale = 1 + 0.018 * lift;
            return Transform(
              alignment: Alignment.center,
              // Keep the pointer region fixed while the card tilts beneath it.
              transformHitTests: false,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..translateByDouble(0, -4 * lift, 0, 1)
                ..rotateX(-tilt.dy * 0.055)
                ..rotateY(tilt.dx * 0.055)
                ..scaleByDouble(scale, scale, scale, 1),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: theme.style.borderRadius.lg,
                  ),
                  shadows: [
                    BoxShadow(
                      color: const Color(0xFF000000)
                          .withValues(alpha: 0.16 * hoverProgress),
                      blurRadius: 18 * hoverProgress,
                      offset: Offset(0, 8 * hoverProgress),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onTap: () {
              final onPosterTap = widget.onPosterTap;
              if (onPosterTap != null) {
                onPosterTap(posterUrl);
              } else {
                widget.onTap?.call();
              }
            },
            child: _buildFrame(
              hoverProgress: hoverProgress,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: widget.aspectRatio ?? 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PosterHero(
                          tag: widget.heroTag,
                          borderRadius: theme.style.borderRadius.md,
                          child: ratingLabel != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    image,
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: DecoratedBox(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x00000000),
                                              Color(0xB3000000),
                                            ],
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            10,
                                            24,
                                            10,
                                            8,
                                          ),
                                          child: Text(
                                            ratingLabel,
                                            textAlign: TextAlign.right,
                                            style: theme.typography.body.sm
                                                .copyWith(
                                                  color: const Color(
                                                    0xFFE2BB6A,
                                                  ),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : image,
                        ),
                        if (widget.posterAction case final action?)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: GestureDetector(
                              // A disabled action must not fall through to play.
                              behavior: HitTestBehavior.opaque,
                              excludeFromSemantics: true,
                              onTap: () {},
                              child: action,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (watched != null && watched > 0) ...[
                    const SizedBox(height: 6),
                    MediaProgressBar(value: watched),
                  ] else if (widget.reserveMetadataSpace)
                    const SizedBox(height: 9),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.displayTitle,
                    textAlign: widget.textAlign,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.sm,
                  ),
                  if (subtitle != null || widget.reserveMetadataSpace) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? '',
                      textAlign: widget.textAlign,
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
          ),
        ),
      ),
    );
  }

  Widget _buildFrame({required double hoverProgress, required Widget child}) =>
      widget.framed
      ? Surface(
          padding: 10,
          translucent: widget.translucent,
          hoverProgress: hoverProgress,
          child: child,
        )
      : child;
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
