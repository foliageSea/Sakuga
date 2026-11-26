import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../core/images/artwork_cache.dart';
import '../../data/media_server/media_models.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';

/// Display title of [item], naming untitled seasons by their number.
String detailItemTitle(BuildContext context, MediaItem item) {
  if (item.name.trim().isNotEmpty || item.type != MediaType.season) {
    return item.name;
  }
  return switch (item.indexNumber) {
    0 => context.l10n.specials,
    final number? => context.l10n.seasonNumber(number),
    null => context.l10n.season,
  };
}

/// Series and season artwork title: the logo when available, otherwise (or
/// when the logo fails to load) the item title in display type.
class MediaTitleArt extends StatelessWidget {
  const MediaTitleArt({
    required this.item,
    required this.onDark,
    this.fallbackItem,
    this.center = false,
    this.pending = false,
    this.keyPrefix = 'detail',
    super.key,
  });

  final MediaItem item;
  final MediaItem? fallbackItem;
  final bool onDark;

  /// Centers the title art in a fixed-height slot, as on the phone layout.
  final bool center;

  /// Keeps the slot empty while a logo may still arrive with full metadata.
  final bool pending;

  /// Prefix of the title and logo widget keys.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final mobile = isMobileLayout(context);
    final alignment = center ? Alignment.bottomCenter : Alignment.bottomLeft;
    final title = Text(
      detailItemTitle(context, item),
      key: ValueKey('$keyPrefix-banner-title'),
      textAlign: center ? TextAlign.center : TextAlign.start,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style:
          (mobile ? theme.typography.display.sm : theme.typography.display.xl)
              .copyWith(
                color: onDark
                    ? const Color(0xFFFFFFFF)
                    : theme.colors.foreground,
              ),
    );
    final logo = item.logo ?? fallbackItem?.logo;
    if (center && logo == null) {
      // A stable slot keeps the facts below from shifting when the title
      // resolves to a logo or text.
      return SizedBox(
        height: 80,
        child: pending
            ? null
            : Align(alignment: Alignment.bottomCenter, child: title),
      );
    }
    if (logo == null) return title;
    return SizedBox(
      width: mobile ? double.infinity : 320,
      height: mobile ? (center ? 80 : 56) : 120,
      child: CachedNetworkImage(
        key: ValueKey('$keyPrefix-logo'),
        imageUrl: logo.url(width: 840),
        httpHeaders: logo.headers,
        cacheKey: artworkCacheKey(logo.url(width: 840), logo.headers),
        cacheManager: ArtworkCacheManager.instance,
        fit: BoxFit.contain,
        alignment: alignment,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => const SizedBox.shrink(),
        errorWidget: (_, _, _) => Align(alignment: alignment, child: title),
      ),
    );
  }
}

/// Star rating shown in detail and featured headers.
class MediaRating extends StatelessWidget {
  const MediaRating({required this.item, required this.onDark, super.key});

  final MediaItem item;
  final bool onDark;

  static double? of(MediaItem item) => switch (item.communityRating) {
    final rating? when rating.isFinite && rating > 0 => rating,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      key: const ValueKey('detail-rating'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          FLucideIcons.star,
          size: isMobileLayout(context) ? 15 : 18,
          color: const Color(0xFFE2BB6A),
        ),
        const SizedBox(width: 6),
        Text(
          of(item)!.toStringAsFixed(1),
          style:
              (isMobileLayout(context)
                      ? theme.typography.body.sm
                      : theme.typography.body.md)
                  .copyWith(
                    color: onDark
                        ? const Color(0xFFFFFFFF)
                        : theme.colors.foreground,
                    fontWeight: FontWeight.w600,
                  ),
        ),
      ],
    );
  }
}

/// Plain-text series and season facts laid out as one line of metadata.
class MediaMetaRow extends StatelessWidget {
  const MediaMetaRow({
    required this.item,
    required this.onDark,
    this.center = false,
    super.key,
  });

  final MediaItem item;
  final bool onDark;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final mobile = isMobileLayout(context);
    final style =
        (mobile && !center
                ? theme.typography.body.sm
                : theme.typography.body.md)
            .copyWith(
              color: onDark
                  ? const Color(0xE6FFFFFF)
                  : theme.colors.mutedForeground,
            );
    final count = item.childCount ?? item.recursiveItemCount;
    final runtimeMinutes = item.runtime?.inMinutes ?? 0;
    return Wrap(
      spacing: mobile ? 14 : 20,
      runSpacing: 4,
      alignment: center ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (MediaRating.of(item) != null)
          MediaRating(item: item, onDark: onDark),
        if (item.productionYear != null)
          Text('${item.productionYear}', style: style),
        if (item.officialRating != null)
          Text(item.officialRating!, style: style),
        if (item.genres.isNotEmpty)
          Text(item.genres.take(3).join(' · '), style: style),
        if (item.type == MediaType.movie && runtimeMinutes > 0)
          Text(context.l10n.libraryDuration(runtimeMinutes), style: style),
        if (item.type == MediaType.season && count != null && count > 0)
          Text(context.l10n.libraryEpisodeCount(count), style: style),
      ],
    );
  }
}
