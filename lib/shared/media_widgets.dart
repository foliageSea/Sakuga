import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/images/disk_image_cache.dart';
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
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaPlaceholder(icon: icon),
        Image(
          image: DiskCachedImage(url, headers: headers),
          fit: fit,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
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

/// A 2:3 poster card with title, optional subtitle and watch progress.
class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({
    required this.client,
    required this.item,
    required this.onTap,
    this.progress,
    super.key,
  });

  final JellyfinClient client;
  final JellyfinItem item;
  final VoidCallback onTap;

  /// Watched fraction between 0 and 1, drawn as a thin bar under the poster.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return GestureDetector(
      onTap: onTap,
      child: Surface(
        padding: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(200, 1200);
            final subtitle = item.displaySubtitle;
            final watched = progress;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: theme.style.borderRadius.md,
                    child: MediaImage(
                      url: client.imageUrl(item, width: width),
                      headers: client.authHeaders,
                    ),
                  ),
                ),
                if (watched != null) ...[
                  const SizedBox(height: 6),
                  _ProgressBar(value: watched),
                ],
                const SizedBox(height: 8),
                Text(
                  item.displayTitle,
                  maxLines: 2,
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
            );
          },
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

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
