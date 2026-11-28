import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/media_server/media_models.dart';
import 'media_widgets.dart';

/// A media thumbnail with a compact title and optional synopsis.
class MediaPreviewCard extends StatefulWidget {
  const MediaPreviewCard({
    required this.item,
    required this.onTap,
    this.artwork,
    this.aspectRatio = 16 / 9,
    this.title,
    this.subtitle,
    this.overview,
    this.posterAction,
    this.heroTag,
    this.playOnTap = false,
    this.zoomOnHover = false,
    this.highlighted = false,
    this.showRating = false,
    this.titleKey,
    this.overviewKey,
    this.durationKey,
    this.playedKey,
    this.highlightKey,
    super.key,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final MediaImageResource? artwork;
  final double aspectRatio;
  final String? title;
  final String? subtitle;
  final String? overview;
  final Widget? posterAction;
  final Object? heroTag;
  final bool playOnTap;
  final bool zoomOnHover;
  final bool highlighted;
  final bool showRating;
  final Key? titleKey;
  final Key? overviewKey;
  final Key? durationKey;
  final Key? playedKey;
  final Key? highlightKey;

  @override
  State<MediaPreviewCard> createState() => _MediaPreviewCardState();
}

class _MediaPreviewCardState extends State<MediaPreviewCard> {
  bool _hovered = false;
  bool _focused = false;

  static String _clock(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(duration.inHours)}:${two(duration.inMinutes % 60)}:'
        '${two(duration.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = context.theme;
    final radius = theme.style.borderRadius.md;
    final artwork = widget.artwork ?? item.poster;
    final duration = item.runtime;
    final rating = item.communityRating;
    final progress = item.progressFraction;
    final subtitle = widget.subtitle?.trim() ?? '';
    final overview = (widget.overview ?? item.overview)?.trim() ?? '';
    final muted = theme.typography.body.sm.copyWith(
      color: theme.colors.mutedForeground,
    );
    Widget badge(
      String text, {
      Key? key,
      Color color = const Color(0xFFFFFFFF),
    }) => DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            key: key,
            style: theme.typography.body.xs.copyWith(color: color),
          ),
        ),
      ),
    );

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hoverDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final image = MediaImage(
      url: artwork?.url(),
      headers: artwork?.headers ?? const {},
    );
    final thumbnail = AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterHero(
              tag: widget.heroTag,
              borderRadius: radius,
              // Zoom the image within its frame; keep the hit area, badges
              // and hero bounds still.
              child: widget.zoomOnHover
                  ? AnimatedScale(
                      scale: _hovered && !reduceMotion ? 1.05 : 1,
                      duration: hoverDuration,
                      curve: Curves.easeOutCubic,
                      child: image,
                    )
                  : image,
            ),
            AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: hoverDuration,
              child: ColoredBox(
                color: const Color(0x33000000),
                child: widget.playOnTap
                    ? const Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0x80000000),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              FLucideIcons.play,
                              size: 22,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            if (duration != null && duration > Duration.zero)
              Positioned(
                top: 8,
                right: 8,
                left: 8,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: badge(_clock(duration), key: widget.durationKey),
                ),
              ),
            if (widget.showRating &&
                rating != null &&
                rating.isFinite &&
                rating > 0)
              Positioned(
                right: 8,
                bottom: progress == null ? 8 : 16,
                child: badge(
                  rating.toStringAsFixed(1),
                  color: const Color(0xFFE2BB6A),
                ),
              ),
            if (progress != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: MediaProgressBar(value: progress),
              ),
            if (widget.highlighted || _focused)
              IgnorePointer(
                child: DecoratedBox(
                  key: widget.highlighted ? widget.highlightKey : null,
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colors.primary, width: 2),
                    borderRadius: radius,
                  ),
                ),
              ),
            if (widget.posterAction case final action?)
              Positioned(
                bottom: progress == null ? 6 : 16,
                left: 6,
                child: GestureDetector(
                  // A disabled badge/action must not fall through to the card.
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: () {},
                  child: action,
                ),
              )
            else if (item.played)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  key: widget.playedKey,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x99000000),
                  ),
                  child: const Icon(
                    FLucideIcons.check,
                    size: 14,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title ?? item.name,
          key: widget.titleKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            overview,
            key: widget.overviewKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ],
      ],
    );
    return Semantics(
      button: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: MouseRegion(
            // Hover should work even when keyboard focus highlights are hidden.
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [thumbnail, const SizedBox(height: 10), text],
            ),
          ),
        ),
      ),
    );
  }
}
