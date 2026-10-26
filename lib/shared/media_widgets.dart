import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/images/disk_image_cache.dart';

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
