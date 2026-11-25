import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_exception.dart';
import '../../core/images/artwork_cache.dart';
import '../../data/media_server/media_server_client.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_profile.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/poster_background.dart';
import '../../shared/widgets.dart';
import '../library/library_providers.dart';
import '../player/player_route.dart';
import 'detail_providers.dart';

/// Seed data carried from a tapped poster card so the detail header and
/// poster [Hero] render on the first frame while full metadata loads.
class DetailRouteExtra {
  const DetailRouteExtra({required this.item, this.posterUrl, this.seriesId});

  final MediaItem item;
  final String? posterUrl;
  final String? seriesId;
}

/// Builds a fade page for [DetailPage] so the poster [Hero] flies smoothly on
/// both push and pop without a competing slide or translate offset.
CustomTransitionPage<void> buildDetailTransitionPage(GoRouterState state) {
  final itemId = state.pathParameters['itemId'] ?? '';
  final extra = state.extra is DetailRouteExtra
      ? state.extra as DetailRouteExtra
      : null;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: FadeTransition(
            opacity: ReverseAnimation(
              CurvedAnimation(
                parent: secondaryAnimation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
            ),
            child: child,
          ),
        ),
    child: DetailPage(
      itemId: itemId,
      initialItem: extra?.item,
      initialPosterUrl: extra?.posterUrl,
      seriesId: extra?.seriesId,
    ),
  );
}

/// Route inputs needed to resolve the detail page's ambient poster background.
typedef DetailBackgroundSpec = ({
  String itemId,
  MediaItem? initialItem,
  String? initialPosterUrl,
});

bool _canReuseSeason(MediaServerClient client, MediaItem? preview) =>
    client.server.type == MediaServerType.ugreen &&
    preview?.type == MediaType.season;

/// Resolves the poster URL and auth headers for [spec], reusing the tapped
/// card's cached poster URL immediately before full metadata arrives.
PosterBackground? watchDetailPosterBackground(
  WidgetRef ref,
  DetailBackgroundSpec? spec,
) {
  if (spec == null || spec.itemId.isEmpty) return null;
  final preview = spec.initialItem?.id == spec.itemId ? spec.initialItem : null;
  final library = ref.watch(libraryViewsProvider);
  return library.when(
    data: (data) {
      final item = _canReuseSeason(data.client, preview)
          ? AsyncData(preview!)
          : ref.watch(
              libraryItemProvider((userId: data.userId, itemId: spec.itemId)),
            );
      final url = item.when(
        data: (value) {
          final poster = value.poster ?? preview?.poster;
          final reusePosterUrl =
              spec.initialPosterUrl != null &&
              poster?.cacheKey == preview?.poster?.cacheKey;
          return (reusePosterUrl ? spec.initialPosterUrl : null) ??
              poster?.url();
        },
        loading: () => spec.initialPosterUrl ?? preview?.poster?.url(),
        error: (_, _) => spec.initialPosterUrl ?? preview?.poster?.url(),
      );
      return url == null
          ? null
          : PosterBackground(
              url: url,
              headers:
                  (item.value?.poster ?? preview?.poster)?.headers ?? const {},
            );
    },
    loading: () {
      final server = ref.watch(activeServerProvider);
      if (server == null) return null;
      final url = spec.initialPosterUrl ?? preview?.poster?.url();
      return url == null
          ? null
          : PosterBackground(
              url: url,
              headers: preview?.poster?.headers ?? const {},
            );
    },
    error: (_, _) => null,
  );
}

class DetailPage extends ConsumerWidget {
  const DetailPage({
    required this.itemId,
    this.initialItem,
    this.initialPosterUrl,
    this.seriesId,
    super.key,
  });

  final String itemId;
  final MediaItem? initialItem;
  final String? initialPosterUrl;
  final String? seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryViewsProvider);
    final preview = initialItem?.id == itemId ? initialItem : null;
    final content = library.when(
      data: (data) => _DetailBody(
        client: data.client,
        userId: data.userId,
        itemId: itemId,
        initialItem: preview,
        initialPosterUrl: initialPosterUrl,
        seriesId: seriesId,
      ),
      loading: () {
        final server = ref.watch(activeServerProvider);
        if (server?.type == MediaServerType.ugreen &&
            server!.userId.isNotEmpty &&
            preview?.type == MediaType.season) {
          return _DetailBody(
            client: ref.watch(mediaServerClientProvider(server)),
            userId: server.userId,
            itemId: itemId,
            initialItem: preview,
            initialPosterUrl: initialPosterUrl,
            seriesId: seriesId,
          );
        }
        if (server != null && preview != null) {
          return _DetailScaffold(
            title: preview.name,
            showLibrary: preview.type == MediaType.season,
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  client: ref.watch(mediaServerClientProvider(server)),
                  item: preview,
                  posterUrl: initialPosterUrl,
                ),
              ),
              const SliverToBoxAdapter(child: LoadingNotice()),
            ],
          );
        }
        return const _DetailScaffold(
          slivers: [SliverToBoxAdapter(child: LoadingNotice())],
        );
      },
      error: (error, _) => _DetailScaffold(
        title: preview?.name,
        showLibrary: preview?.type == MediaType.season,
        slivers: [
          SliverToBoxAdapter(
            child: ErrorNotice(
              error,
              onRetry: () => ref.invalidate(libraryViewsProvider),
            ),
          ),
        ],
      ),
    );
    if (WindowPosterBackgroundScope.hasHost(context)) return content;
    final background = watchDetailPosterBackground(ref, (
      itemId: itemId,
      initialItem: initialItem,
      initialPosterUrl: initialPosterUrl,
    ));
    return WindowPosterBackgroundScope(
      active: background != null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PosterWindowBackground(background: background),
          content,
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.client,
    required this.userId,
    required this.itemId,
    this.initialItem,
    this.initialPosterUrl,
    this.seriesId,
  });

  final MediaServerClient client;
  final String userId;
  final String itemId;
  final MediaItem? initialItem;
  final String? initialPosterUrl;
  final String? seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (userId: userId, itemId: itemId);
    final preview = initialItem;
    // Green Theater seasons are generated from the episode list. Reuse the
    // season card metadata so entering a season fetches episodes only once.
    final item =
        _canReuseSeason(client, preview) &&
            preview != null &&
            preview.id == itemId &&
            (preview.seriesId ?? seriesId) != null
        ? AsyncData(preview)
        : ref.watch(libraryItemProvider(query));
    return item.when(
      data: (value) {
        final parentSeriesId = value.seriesId ?? preview?.seriesId ?? seriesId;
        final reusePosterUrl =
            initialPosterUrl != null &&
            (value.poster ?? preview?.poster)?.cacheKey ==
                preview?.poster?.cacheKey;
        return _DetailScaffold(
          title: _detailItemTitle(context, value),
          showLibrary: value.type == MediaType.season,
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: value,
                posterUrl: reusePosterUrl ? initialPosterUrl : null,
                fallbackItem: preview,
              ),
            ),
            SliverToBoxAdapter(child: _About(item: value)),
            if (client.server.type == MediaServerType.ugreen &&
                value.type == MediaType.movie)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _PlaybackTile(
                    item: value,
                    thumbnail:
                        value.backdrop ??
                        preview?.backdrop ??
                        value.poster ??
                        preview?.poster,
                    translucent: WindowPosterBackgroundScope.isActive(context),
                  ),
                ),
              ),
            if (value.isSeries)
              _Seasons(client: client, userId: userId, series: value),
            if (value.type == MediaType.season)
              if (parentSeriesId != null)
                _Episodes(
                  userId: userId,
                  seriesId: parentSeriesId,
                  seasonId: value.id,
                )
              else
                SliverToBoxAdapter(
                  child: ErrorNotice(
                    const AppException(FailureKind.invalidData),
                    onRetry: () => ref.invalidate(libraryItemProvider(query)),
                  ),
                ),
          ],
        );
      },
      loading: () => _DetailScaffold(
        title: preview?.name,
        showLibrary: preview?.type == MediaType.season,
        slivers: [
          if (preview != null)
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: preview,
                posterUrl: initialPosterUrl,
              ),
            ),
          const SliverToBoxAdapter(child: LoadingNotice()),
        ],
      ),
      error: (error, _) => _DetailScaffold(
        title: preview?.name,
        showLibrary: preview?.type == MediaType.season,
        slivers: [
          if (preview != null)
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: preview,
                posterUrl: initialPosterUrl,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: preview == null ? 0 : 24),
              child: ErrorNotice(
                error,
                onRetry: () => ref.invalidate(libraryItemProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The detail page shell: the back bar is pinned above the scrolling content
/// so it stays reachable in every state, including loading and errors.
class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.slivers,
    this.title,
    this.showLibrary = false,
  });

  final List<Widget> slivers;
  final String? title;
  final bool showLibrary;

  @override
  Widget build(BuildContext context) {
    final mobileShell =
        isMobileLayout(context) &&
        WindowPosterBackgroundScope.hasShell(context);
    return PageScrollView(
      header: mobileShell
          ? null
          : _BackBar(title: title, showLibrary: showLibrary),
      animate: false,
      transparent: true,
      slivers: slivers,
    );
  }
}

/// Frosted outline button style used by detail navigation and filter actions
/// when an ambient poster background is active.
FButtonStyleDelta detailOutlineButtonStyle(BuildContext context) {
  if (!WindowPosterBackgroundScope.isActive(context)) {
    return const .context();
  }
  final theme = context.theme;
  final colors = theme.colors;
  final dark = colors.brightness == Brightness.dark;
  final fill = colors.card.withValues(alpha: dark ? 0.56 : 0.64);
  final hoverFill = colors.card.withValues(alpha: dark ? 0.72 : 0.80);
  final borderColor = dark
      ? colors.border
      : colors.foreground.withValues(alpha: 0.09);
  return .delta(
    decoration: .delta([
      .base(
        .shapeDelta(
          color: fill,
          shape: RoundedSuperellipseBorder(
            side: BorderSide(
              color: borderColor,
              width: theme.style.borderWidth,
            ),
            borderRadius: theme.style.borderRadius.md,
          ),
        ),
      ),
      .exact({.hovered, .pressed, .selected}, .shapeDelta(color: hoverFill)),
    ]),
  );
}

/// The detail title displayed in the mobile shell's app bar.
class DetailHeaderTitle extends ConsumerWidget {
  const DetailHeaderTitle({required this.spec, super.key});

  final DetailBackgroundSpec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryViewsProvider).value;
    final preview = spec.initialItem;
    final item = library == null
        ? null
        : _canReuseSeason(library.client, preview) && preview?.id == spec.itemId
        ? preview
        : ref
              .watch(
                libraryItemProvider((
                  userId: library.userId,
                  itemId: spec.itemId,
                )),
              )
              .value;
    final value = item ?? spec.initialItem;
    return Row(
      children: [
        Expanded(
          child: _DetailTitle(
            value == null ? '' : _detailItemTitle(context, value),
          ),
        ),
        if (value?.type == MediaType.season) ...[
          const SizedBox(width: 8),
          const _BackToLibraryButton(),
        ],
      ],
    );
  }
}

class _DetailTitle extends StatelessWidget {
  const _DetailTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    key: const ValueKey('detail-title'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.theme.typography.body.lg,
  );
}

class _BackBar extends StatelessWidget {
  const _BackBar({this.title, this.showLibrary = false});

  final String? title;
  final bool showLibrary;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Row(
      children: [
        FButton.icon(
          key: const ValueKey('detail-back'),
          variant: .ghost,
          size: .sm,
          semanticsLabel: l.back,
          onPress: () => popDetailRoute(context),
          child: const Icon(FLucideIcons.arrowLeft),
        ),
        if (title != null) ...[
          const SizedBox(width: 12),
          Expanded(child: _DetailTitle(title!)),
        ],
        if (showLibrary) ...[
          const SizedBox(width: 12),
          const _BackToLibraryButton(),
        ],
      ],
    );
  }
}

class _BackToLibraryButton extends StatelessWidget {
  const _BackToLibraryButton();

  @override
  Widget build(BuildContext context) => FTooltip(
    tipBuilder: (context, controller) => Text(context.l10n.backToLibrary),
    child: FButton.icon(
      key: const ValueKey('detail-back-to-library'),
      variant: .ghost,
      size: .sm,
      semanticsLabel: context.l10n.backToLibrary,
      onPress: () => context.go('/library'),
      child: const Icon(FLucideIcons.film),
    ),
  );
}

/// Pops the detail route, falling back to the library when the page was opened
/// directly, e.g. from a deep link.
void popDetailRoute(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/library');
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.client,
    required this.item,
    this.posterUrl,
    this.fallbackItem,
  });

  final MediaServerClient client;
  final MediaItem item;
  final String? posterUrl;
  final MediaItem? fallbackItem;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final mobile = isMobileLayout(context);
    final seriesDetail = item.isSeries || item.type == MediaType.season;
    final posterWidth = mobile ? 96.0 : (seriesDetail ? 160.0 : 132.0);
    final poster = AspectRatio(
      aspectRatio: 2 / 3,
      child: PosterHero(
        tag: posterHeroTag(item.id),
        borderRadius: theme.style.borderRadius.md,
        child: MediaImage(
          url: posterUrl ?? (item.poster ?? fallbackItem?.poster)?.url(),
          headers: (item.poster ?? fallbackItem?.poster)?.headers ?? const {},
        ),
      ),
    );
    final backdrop = MediaImage(
      url: (item.backdrop ?? fallbackItem?.backdrop)?.url(width: 1920),
      headers: (item.backdrop ?? fallbackItem?.backdrop)?.headers ?? const {},
    );
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: theme.style.borderRadius.lg,
            child: AspectRatio(aspectRatio: 16 / 9, child: backdrop),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: posterWidth, child: poster),
              const SizedBox(width: 12),
              Expanded(
                child: _TitleBlock(
                  item: item,
                  fallbackItem: fallbackItem,
                  onDark: false,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: theme.style.borderRadius.lg,
      child: SizedBox(
        height: seriesDetail ? 420 : 340,
        child: Stack(
          fit: StackFit.expand,
          children: [
            backdrop,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1A000000), Color(0xF2000000)],
                  stops: [0.25, 1],
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(width: posterWidth, child: poster),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _TitleBlock(
                      item: item,
                      fallbackItem: fallbackItem,
                      onDark: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.item,
    required this.onDark,
    this.fallbackItem,
  });

  final MediaItem item;
  final MediaItem? fallbackItem;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final muted = onDark
        ? const Color(0xCCFFFFFF)
        : theme.colors.mutedForeground;
    final background = onDark ? const Color(0x33FFFFFF) : theme.colors.muted;
    final logo = item.logo ?? fallbackItem?.logo;
    final mobile = isMobileLayout(context);
    final bannerTitle = item.isSeries || item.type == MediaType.season
        ? Text(
            _detailItemTitle(context, item),
            key: const ValueKey('detail-banner-title'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                (mobile
                        ? theme.typography.display.md
                        : theme.typography.display.xl)
                    .copyWith(
                      color: onDark
                          ? const Color(0xFFFFFFFF)
                          : theme.colors.foreground,
                    ),
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          SizedBox(
            width: 420,
            height: mobile ? 80 : 120,
            child: CachedNetworkImage(
              key: const ValueKey('detail-logo'),
              imageUrl: logo.url(width: 840),
              httpHeaders: logo.headers,
              cacheKey: artworkCacheKey(logo.url(width: 840), logo.headers),
              cacheManager: ArtworkCacheManager.instance,
              fit: BoxFit.contain,
              alignment: Alignment.bottomLeft,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => const SizedBox.shrink(),
              errorWidget: (_, _, _) => bannerTitle == null
                  ? const SizedBox.shrink()
                  : Align(alignment: Alignment.bottomLeft, child: bannerTitle),
            ),
          ),
          const SizedBox(height: 10),
        ] else if (bannerTitle != null) ...[
          bannerTitle,
          const SizedBox(height: 10),
        ],
        if (item.communityRating case final rating?
            when rating.isFinite && rating > 0) ...[
          Row(
            key: const ValueKey('detail-rating'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FLucideIcons.star, size: 18, color: Color(0xFFE2BB6A)),
              const SizedBox(width: 6),
              Text(
                rating.toStringAsFixed(1),
                style: theme.typography.body.md.copyWith(
                  color: onDark
                      ? const Color(0xFFFFFFFF)
                      : theme.colors.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (item.productionYear != null)
              _Tag(
                text: '${item.productionYear}',
                foreground: muted,
                background: background,
              ),
            if (item.officialRating != null)
              _Tag(
                text: item.officialRating!,
                foreground: muted,
                background: background,
              ),
            for (final genre in item.genres.take(3))
              _Tag(text: genre, foreground: muted, background: background),
          ],
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.foreground,
    required this.background,
  });

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: context.theme.typography.body.xs.copyWith(color: foreground),
    ),
  );
}

class _About extends StatelessWidget {
  const _About({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final overview = item.overview?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overview.isNotEmpty) ...[
            _SectionTitle(l.synopsis),
            const SizedBox(height: 8),
            Text(overview, style: theme.typography.body.sm),
          ],
          if (item.people.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle(l.cast),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in item.people.take(12))
                  _PersonChip(person: person),
              ],
            ),
          ],
          if (item.studios.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle(l.studios),
            const SizedBox(height: 8),
            Text(
              item.studios.join(' · '),
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.theme.typography.body.lg.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person});

  final MediaPerson person;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final ambient = WindowPosterBackgroundScope.isActive(context);
    final dark = colors.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ambient
            ? colors.card.withValues(alpha: dark ? 0.52 : 0.60)
            : colors.muted,
        border: ambient
            ? Border.all(
                color: dark
                    ? colors.border
                    : colors.foreground.withValues(alpha: 0.08),
                width: theme.style.borderWidth,
              )
            : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(person.name, style: theme.typography.body.sm),
          if (person.role.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              person.role,
              style: theme.typography.body.xs.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _detailItemTitle(BuildContext context, MediaItem item) {
  if (item.name.trim().isNotEmpty || item.type != MediaType.season) {
    return item.name;
  }
  return switch (item.indexNumber) {
    0 => context.l10n.specials,
    final number? => context.l10n.seasonNumber(number),
    null => context.l10n.season,
  };
}

class _Seasons extends ConsumerWidget {
  const _Seasons({
    required this.client,
    required this.userId,
    required this.series,
  });
  final MediaServerClient client;
  final String userId;
  final MediaItem series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (userId: userId, seriesId: series.id);
    final seasons = ref.watch(seriesSeasonsProvider(query));
    final heading = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: _SectionTitle(context.l10n.seasons),
      ),
    );
    return seasons.when(
      data: (values) {
        if (values.isEmpty) {
          return _Episodes(userId: userId, seriesId: series.id);
        }
        return SliverMainAxisGroup(
          slivers: [
            heading,
            SliverToBoxAdapter(
              child: Wrap(
                spacing: 16,
                runSpacing: 20,
                children: [
                  for (final season in values)
                    SizedBox(
                      width: isMobileLayout(context) ? 136 : 168,
                      child: _SeasonCard(
                        client: client,
                        season: season,
                        series: series,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => SliverMainAxisGroup(
        slivers: [
          heading,
          const SliverToBoxAdapter(child: LoadingNotice()),
        ],
      ),
      error: (error, _) => SliverMainAxisGroup(
        slivers: [
          heading,
          SliverToBoxAdapter(
            child: ErrorNotice(
              error,
              onRetry: () => ref.invalidate(seriesSeasonsProvider(query)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.client,
    required this.season,
    required this.series,
  });
  final MediaServerClient client;
  final MediaItem season;
  final MediaItem series;

  @override
  Widget build(BuildContext context) {
    final label = _detailItemTitle(context, season);
    final preview = MediaItem(
      id: season.id,
      name: label,
      type: MediaType.season,
      poster: season.poster ?? series.poster,
      backdrop: season.backdrop ?? series.backdrop,
      logo: season.logo,
      seriesId: season.seriesId ?? series.id,
      seriesName: season.seriesName ?? series.name,
      indexNumber: season.indexNumber,
      childCount: season.childCount,
      recursiveItemCount: season.recursiveItemCount,
      productionYear: season.productionYear,
      communityRating: season.communityRating,
      officialRating: season.officialRating,
      genres: season.genres,
    );
    final count = season.childCount ?? season.recursiveItemCount;
    final metadata = [
      if (season.productionYear != null) '${season.productionYear}',
      if (count != null) context.l10n.libraryEpisodeCount(count),
    ].join(' · ');
    return MediaPosterCard(
      key: ValueKey('detail-season-${season.id}'),
      client: client,
      item: preview,
      subtitle: metadata.isNotEmpty ? metadata : null,
      heroTag: posterHeroTag(season.id),
      onPosterTap: (posterUrl) => context.push(
        '/library/${season.id}',
        extra: DetailRouteExtra(
          item: preview,
          posterUrl: posterUrl,
          seriesId: series.id,
        ),
      ),
    );
  }
}

class _Episodes extends ConsumerWidget {
  const _Episodes({
    required this.userId,
    required this.seriesId,
    this.seasonId,
  });
  final String userId;
  final String seriesId;
  final String? seasonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (userId: userId, seriesId: seriesId, seasonId: seasonId);
    final episodes = ref.watch(seriesEpisodesProvider(query));
    final ambient = WindowPosterBackgroundScope.isActive(context);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SectionTitle(context.l10n.episodes),
                if (episodes.value case final values?)
                  Text(
                    context.l10n.libraryEpisodeCount(values.length),
                    style: context.theme.typography.body.sm.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
        ),
        ...episodes.when(
          data: (values) => values.isEmpty
              ? [
                  SliverToBoxAdapter(
                    child: EmptyNotice(
                      context.l10n.noItems,
                      translucent: ambient,
                    ),
                  ),
                ]
              : [
                  SliverList.builder(
                    itemCount: values.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PlaybackTile(
                        item: values[index],
                        thumbnail: values[index].poster,
                        translucent: ambient,
                      ),
                    ),
                  ),
                ],
          loading: () => [const SliverToBoxAdapter(child: LoadingNotice())],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: ErrorNotice(
                error,
                onRetry: () => ref.invalidate(seriesEpisodesProvider(query)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackTile extends StatelessWidget {
  const _PlaybackTile({
    required this.item,
    required this.thumbnail,
    this.translucent = false,
  });
  final MediaItem item;
  final MediaImageResource? thumbnail;
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final code = item.isEpisode ? item.episodeCode : null;
    final progress = item.progressFraction;
    final overview = item.isEpisode ? item.overview?.trim() ?? '' : '';
    final keyPrefix = item.isEpisode ? 'detail-episode' : 'detail-movie';
    final title = !item.isEpisode || item.indexNumber == null
        ? item.name
        : context.l10n.episodeTitle(item.indexNumber!, item.name);
    final duration = item.runtime;
    final metadata = [
      ?code,
      if (duration != null && duration > Duration.zero)
        context.l10n.libraryDuration(duration.inMinutes),
    ].join(' · ');
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: ValueKey('$keyPrefix-title-${item.id}'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w500),
        ),
        if (metadata.isNotEmpty || item.played) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (metadata.isNotEmpty)
                Text(
                  metadata,
                  key: ValueKey('$keyPrefix-metadata-${item.id}'),
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              if (item.played)
                Icon(
                  FLucideIcons.check,
                  size: 14,
                  color: theme.colors.mutedForeground,
                ),
            ],
          ),
        ],
        if (overview.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            overview,
            key: ValueKey('$keyPrefix-overview-${item.id}'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
      ],
    );
    final thumbnailFrame = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: theme.style.borderRadius.md,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaImage(
                  url: thumbnail?.url(),
                  headers: thumbnail?.headers ?? const {},
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x66000000),
                    ),
                    child: const Icon(
                      FLucideIcons.play,
                      size: 20,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          MediaProgressBar(value: progress),
        ],
      ],
    );
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('$keyPrefix-${item.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(playerLocation(item.id)),
          child: Surface(
            padding: 12,
            translucent: translucent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 320) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      thumbnailFrame,
                      const SizedBox(height: 12),
                      information,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: constraints.maxWidth < 600 ? 112 : 240,
                      child: thumbnailFrame,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: information),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
