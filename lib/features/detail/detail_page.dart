import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_exception.dart';
import '../../data/media_server/media_server_client.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_profile.dart';
import '../../shared/immersive.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/poster_background.dart';
import '../../shared/widgets.dart';
import '../library/library_providers.dart';
import '../player/player_route.dart';
import 'detail_providers.dart';
import 'media_header.dart';

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
            hasArtwork: true,
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  client: ref.watch(mediaServerClientProvider(server)),
                  item: preview,
                  posterUrl: initialPosterUrl,
                  pending: true,
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
        // A series with exactly one season skips season selection and lists
        // that season's episodes directly, reusing the season list request.
        final singleSeason = value.isSeries
            ? switch (ref
                  .watch(
                    seriesSeasonsProvider((userId: userId, seriesId: value.id)),
                  )
                  .value) {
                [final only] => only,
                _ => null,
              }
            : null;
        final reusePosterUrl =
            initialPosterUrl != null &&
            (value.poster ?? preview?.poster)?.cacheKey ==
                preview?.poster?.cacheKey;
        return _DetailScaffold(
          title: detailItemTitle(context, value),
          showLibrary: value.type == MediaType.season,
          hasArtwork: true,
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: value,
                posterUrl: reusePosterUrl ? initialPosterUrl : null,
                fallbackItem: preview,
                userId: userId,
                seriesId: parentSeriesId,
                seasonId: singleSeason?.id,
              ),
            ),
            if (value.isSeries)
              if (singleSeason != null)
                _Episodes(
                  userId: userId,
                  seriesId: value.id,
                  seasonId: singleSeason.id,
                )
              else
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
            // Season selection stays focused on seasons; cast and studios
            // belong to the episode views.
            if (!value.isSeries ||
                singleSeason != null ||
                isMobileLayout(context))
              SliverToBoxAdapter(child: _Credits(item: value)),
          ],
        );
      },
      loading: () => _DetailScaffold(
        title: preview?.name,
        showLibrary: preview?.type == MediaType.season,
        hasArtwork: preview != null,
        slivers: [
          if (preview != null)
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: preview,
                posterUrl: initialPosterUrl,
                userId: userId,
                seriesId: preview.seriesId ?? seriesId,
                pending: true,
              ),
            ),
          const SliverToBoxAdapter(child: LoadingNotice()),
        ],
      ),
      error: (error, _) => _DetailScaffold(
        title: preview?.name,
        showLibrary: preview?.type == MediaType.season,
        hasArtwork: preview != null,
        slivers: [
          if (preview != null)
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: preview,
                posterUrl: initialPosterUrl,
                userId: userId,
                seriesId: preview.seriesId ?? seriesId,
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

/// Keeps navigation reachable in every state. A host shell can overlay it
/// on the artwork; standalone detail routes retain their pinned back bar.
class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.slivers,
    this.title,
    this.showLibrary = false,
    this.hasArtwork = false,
  });

  final List<Widget> slivers;
  final bool hasArtwork;
  final String? title;
  final bool showLibrary;

  @override
  Widget build(BuildContext context) {
    final inset = ImmersiveScope.insetOf(context);
    final shellHasHeader = WindowPosterBackgroundScope.hasShell(context);
    return PageScrollView(
      header: shellHasHeader
          ? null
          : _BackBar(title: title, showLibrary: showLibrary),
      flushTop: inset != null,
      maxWidth: inset == null ? 1440 : double.infinity,
      animate: false,
      transparent: true,
      slivers: [
        if (inset != null && !hasArtwork)
          SliverToBoxAdapter(
            child: SizedBox(
              height: inset + 24,
              child: _DetailChromeScrim(inset),
            ),
          ),
        ...slivers,
      ],
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
            value == null ? '' : detailItemTitle(context, value),
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
    this.userId,
    this.seriesId,
    this.seasonId,
    this.pending = false,
  });

  final MediaServerClient client;
  final MediaItem item;
  final String? posterUrl;
  final MediaItem? fallbackItem;

  /// The only season of a series, whose episodes drive the play action.
  final String? seasonId;

  /// Account used to resolve the primary play action of series and seasons.
  final String? userId;

  /// Parent series of a season, needed to load its episodes for playback.
  final String? seriesId;

  /// Whether [item] is the tapped card's preview while full metadata loads.
  /// Phone artwork waits for the real backdrop instead of swapping images.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final mobile = isMobileLayout(context);
    final seriesDetail = item.isSeries || item.type == MediaType.season;
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
    final backdropImage =
        item.backdrop ??
        fallbackItem?.backdrop ??
        item.poster ??
        fallbackItem?.poster;
    final backdrop = MediaImage(
      key: const ValueKey('detail-desktop-art'),
      url: backdropImage?.url(width: 1920),
      headers: backdropImage?.headers ?? const {},
    );
    final playButton = seriesDetail
        ? _PlayButton(
            userId: userId,
            seriesId: item.isSeries
                ? item.id
                : seriesId ?? item.seriesId ?? fallbackItem?.seriesId,
            seasonId: item.isSeries ? seasonId : item.id,
          )
        : item.type == MediaType.movie
        ? FButton(
            key: const ValueKey('detail-play'),
            size: .lg,
            prefix: const Icon(FLucideIcons.play),
            onPress: pending
                ? null
                : () => context.push(playerLocation(item.id)),
            child: Text(
              !item.played &&
                      (item.playbackPosition ?? Duration.zero) > Duration.zero
                  ? context.l10n.continueWatching
                  : context.l10n.playPlayback,
            ),
          )
        : null;
    final overview = item.overview?.trim() ?? '';
    final inset = ImmersiveScope.insetOf(context);
    final chromeHeight = inset ?? 0;
    final pageInset = pagePadding(context);
    final artHeight = headerArtworkHeight(context);
    if (mobile) {
      // Phones: edge-to-edge artwork fading into the page, with the centered
      // title art, facts, play action and synopsis stacked beneath it.
      final topBleed = inset == null ? pageInset : 0.0;
      final mobileArt =
          item.backdrop ??
          fallbackItem?.backdrop ??
          (pending ? null : item.poster ?? fallbackItem?.poster);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: artHeight - topBleed,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -topBleed,
                  left: -pageInset,
                  right: -pageInset,
                  bottom: 0,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                      stops: [0.55, 1],
                    ).createShader(bounds),
                    // No poster hero here: flying a 2:3 card into this wide
                    // frame and then swapping in the backdrop made it jump.
                    child: mobileArt == null
                        ? const SizedBox.shrink()
                        : MediaImage(
                            key: const ValueKey('detail-mobile-art'),
                            url: mobileArt.url(width: 1280),
                            headers: mobileArt.headers,
                          ),
                  ),
                ),
                if (inset != null)
                  Positioned(
                    top: 0,
                    left: -pageInset,
                    right: -pageInset,
                    height: chromeHeight + 48,
                    child: _DetailChromeScrim(chromeHeight),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MediaTitleArt(
                    item: item,
                    fallbackItem: fallbackItem,
                    onDark: false,
                    center: true,
                    pending: pending,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          MediaMetaRow(item: item, onDark: false, center: true),
          if (playButton != null) ...[const SizedBox(height: 18), playButton],
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Overview(text: overview, maxLines: 2, onDark: false),
          ],
        ],
      );
    }
    final bleed = inset == null ? 0.0 : pageInset;
    final background = Stack(
      fit: StackFit.expand,
      children: [
        backdrop,
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xE6000000)],
              stops: [0.35, 1],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0x99000000), Color(0x00000000)],
              stops: [0, 0.6],
            ),
          ),
        ),
        if (inset != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: chromeHeight + 48,
            child: _DetailChromeScrim(chromeHeight),
          ),
      ],
    );
    return ClipRRect(
      borderRadius: theme.style.borderRadius.lg,
      clipBehavior: inset == null ? Clip.antiAlias : Clip.none,
      child: SizedBox(
        height: artHeight,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              left: -bleed,
              right: -bleed,
              child: inset == null
                  ? background
                  : ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                        stops: [0.92, 1],
                      ).createShader(bounds),
                      child: background,
                    ),
            ),
            Positioned(
              left: 32,
              right: 32,
              bottom: 28,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(width: 150, child: poster),
                  const SizedBox(width: 28),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final title = MediaTitleArt(
                          item: item,
                          fallbackItem: fallbackItem,
                          onDark: true,
                        );
                        final details = [
                          MediaMetaRow(item: item, onDark: true),
                          if (overview.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _Overview(
                              text: overview,
                              maxLines: 3,
                              onDark: true,
                            ),
                          ],
                        ];
                        if (constraints.maxWidth < 720) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 12),
                              ...details,
                              const SizedBox(height: 20),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 360,
                                ),
                                child: playButton,
                              ),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 320,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.bottomLeft,
                                    child: title,
                                  ),
                                  const SizedBox(height: 20),
                                  ?playButton,
                                ],
                              ),
                            ),
                            const SizedBox(width: 40),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: details,
                              ),
                            ),
                          ],
                        );
                      },
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

/// Keeps the overlaid controls readable on bright or still-loading artwork.
class _DetailChromeScrim extends StatelessWidget {
  const _DetailChromeScrim(this.inset);

  final double inset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Color(0xB3000000),
              Color(0x99000000),
              Color(0x00000000),
            ],
            stops: [0, (inset / constraints.maxHeight).clamp(0.0, 1.0), 1],
          ),
        ),
      ),
    ),
  );
}

/// A clamped synopsis that offers the full text in a dialog only when it
/// actually overflows.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.text,
    required this.maxLines,
    required this.onDark,
  });

  final String text;
  final int maxLines;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final style = (onDark ? theme.typography.body.md : theme.typography.body.sm)
        .copyWith(
          color: onDark ? const Color(0xE6FFFFFF) : theme.colors.foreground,
          height: 1.6,
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: double.infinity,
              child: Text(
                text,
                key: const ValueKey('detail-overview'),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (overflows)
              Semantics(
                button: true,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: const ValueKey('detail-overview-more'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showFullOverview(context),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        context.l10n.showMore,
                        style: style.copyWith(
                          fontWeight: FontWeight.w600,
                          color: onDark
                              ? const Color(0xFFFFFFFF)
                              : theme.colors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showFullOverview(BuildContext context) {
    final l = context.l10n;
    return showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.synopsis,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    key: const ValueKey('detail-overview-full'),
                    style: context.theme.typography.body.sm.copyWith(
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FButton(
                  key: const ValueKey('detail-overview-close'),
                  variant: .outline,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => Navigator.of(context).pop(),
                  child: Text(l.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Primary series and season action: plays the episode to watch next.
///
/// Seasons resolve the episode from their already-loaded episode list. Series
/// load the full episode list only when pressed, so opening a series does not
/// fetch every episode up front.
class _PlayButton extends ConsumerStatefulWidget {
  const _PlayButton({
    required this.userId,
    required this.seriesId,
    required this.seasonId,
  });

  final String? userId;
  final String? seriesId;
  final String? seasonId;

  @override
  ConsumerState<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends ConsumerState<_PlayButton> {
  bool _busy = false;
  Object? _error;

  EpisodesQuery? get _query {
    final userId = widget.userId;
    final seriesId = widget.seriesId;
    if (userId == null || seriesId == null) return null;
    return (userId: userId, seriesId: seriesId, seasonId: widget.seasonId);
  }

  Future<void> _playSeries(EpisodesQuery query) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final episodes = await ref.read(seriesEpisodesProvider(query).future);
      if (!mounted) return;
      final next = resolveNextEpisode(episodes);
      if (next == null) {
        setState(() => _error = const AppException(FailureKind.invalidData));
        return;
      }
      context.push(playerLocation(next.episode.id));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _button(String label, VoidCallback? onPress) => FButton(
    key: const ValueKey('detail-play'),
    size: .lg,
    onPress: onPress,
    prefix: _busy
        ? const SizedBox(width: 18, height: 18, child: FCircularProgress())
        : const Icon(FLucideIcons.play),
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final query = _query;
    if (query == null) return _button(l.playPlayback, null);
    if (query.seasonId == null) {
      final button = _button(
        l.playPlayback,
        _busy ? null : () => _playSeries(query),
      );
      final error = _error;
      if (error == null) return button;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: ErrorNotice(error)),
        ],
      );
    }
    return ref
        .watch(seriesEpisodesProvider(query))
        .when(
          data: (episodes) {
            final next = resolveNextEpisode(episodes);
            if (next == null) return const SizedBox.shrink();
            final number = next.episode.indexNumber;
            final label = number == null
                ? l.playPlayback
                : next.resume
                ? l.resumeEpisodeNumber(number)
                : l.playEpisodeNumber(number);
            return _button(
              label,
              () => context.push(playerLocation(next.episode.id)),
            );
          },
          loading: () => _button(l.playPlayback, null),
          error: (_, _) => const SizedBox.shrink(),
        );
  }
}

class _Credits extends StatelessWidget {
  const _Credits({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final sections = <List<Widget>>[
      if (item.people.isNotEmpty)
        [
          _SectionTitle(l.cast),
          const SizedBox(height: 12),
          _CastRow(people: item.people),
        ],
      if (item.studios.isNotEmpty)
        [
          _SectionTitle(l.studios),
          const SizedBox(height: 8),
          Text(
            item.studios.join(' · '),
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
    ];
    if (sections.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('detail-about'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, section) in sections.indexed) ...[
            if (index > 0) const SizedBox(height: 24),
            ...section,
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

/// A horizontally scrolling strip of cast and crew headshots.
class _CastRow extends StatelessWidget {
  const _CastRow({required this.people});

  final List<MediaPerson> people;

  @override
  Widget build(BuildContext context) {
    final width = isMobileLayout(context) ? 84.0 : 104.0;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: SingleChildScrollView(
        key: const ValueKey('detail-cast'),
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, person) in people.take(24).indexed) ...[
              if (index > 0) const SizedBox(width: 14),
              SizedBox(
                width: width,
                child: _PersonCard(person: person),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final MediaPerson person;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final image = person.image;
    final role = person.role.isNotEmpty ? person.role : person.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: theme.style.borderRadius.lg,
            child: MediaImage(
              url: image?.url(width: 240),
              headers: image?.headers ?? const {},
              icon: FLucideIcons.user,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          person.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.typography.body.sm,
        ),
        if (role.isNotEmpty)
          Text(
            role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.typography.body.xs.copyWith(
              color: colors.mutedForeground,
            ),
          ),
      ],
    );
  }
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
        if (isMobileLayout(context) && values.length > 1) {
          return _SeasonTabsEpisodes(
            userId: userId,
            series: series,
            seasons: values,
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            heading,
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const gap = 16.0;
                  // Phones fill the row evenly instead of leaving a ragged gap.
                  final mobile = isMobileLayout(context);
                  final columns = ((constraints.maxWidth + gap) / (128 + gap))
                      .floor()
                      .clamp(2, 4);
                  final width = mobile
                      ? (constraints.maxWidth - gap * (columns - 1)) / columns
                      : 168.0;
                  return Wrap(
                    spacing: gap,
                    runSpacing: 20,
                    children: [
                      for (final season in values)
                        SizedBox(
                          width: width,
                          child: _SeasonCard(
                            client: client,
                            season: season,
                            series: series,
                          ),
                        ),
                    ],
                  );
                },
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

/// Phone layout for multi-season series: season tabs switch the episodes
/// listed in place instead of opening a separate season page.
class _SeasonTabsEpisodes extends StatefulWidget {
  const _SeasonTabsEpisodes({
    required this.userId,
    required this.series,
    required this.seasons,
  });

  final String userId;
  final MediaItem series;
  final List<MediaItem> seasons;

  @override
  State<_SeasonTabsEpisodes> createState() => _SeasonTabsEpisodesState();
}

class _SeasonTabsEpisodesState extends State<_SeasonTabsEpisodes> {
  String? _selected;

  /// The first regular season, so specials are not the default.
  String get _seasonId {
    final selected = _selected;
    if (selected != null && widget.seasons.any((s) => s.id == selected)) {
      return selected;
    }
    return widget.seasons
        .firstWhere(
          (season) => season.indexNumber != 0,
          orElse: () => widget.seasons.first,
        )
        .id;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final seasonId = _seasonId;
    final tabs = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final season in widget.seasons)
              GestureDetector(
                key: ValueKey('detail-season-tab-${season.id}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selected = season.id),
                child: Semantics(
                  button: true,
                  selected: season.id == seasonId,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      right: 22,
                      top: 4,
                      bottom: 4,
                    ),
                    child: Text(
                      detailItemTitle(context, season),
                      style: theme.typography.body.md.copyWith(
                        fontWeight: season.id == seasonId
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: season.id == seasonId
                            ? theme.colors.foreground
                            : theme.colors.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return _Episodes(
      key: ValueKey('detail-season-episodes-$seasonId'),
      userId: widget.userId,
      seriesId: widget.series.id,
      seasonId: seasonId,
      tabs: tabs,
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
    final label = detailItemTitle(context, season);
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

class _Episodes extends ConsumerStatefulWidget {
  const _Episodes({
    required this.userId,
    required this.seriesId,
    this.seasonId,
    this.tabs,
    super.key,
  });
  final String userId;
  final String seriesId;
  final String? seasonId;

  /// Season switcher shown between the heading and the episodes on phones.
  final Widget? tabs;

  @override
  ConsumerState<_Episodes> createState() => _EpisodesState();
}

class _EpisodesState extends ConsumerState<_Episodes> {
  static const _chipSize = 64.0;

  final _scroll = ScrollController();
  bool _grid = false;
  String? _revealed;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Phones show compact numbered chips; wider layouts show 16:9 cards.
  double _itemWidth(BuildContext context) =>
      isMobileLayout(context) ? _chipSize : 300;

  double _itemGap(BuildContext context) => isMobileLayout(context) ? 10 : 16;

  /// Brings the next episode into view once per episode list.
  void _revealNext(List<MediaItem> episodes, String? nextId) {
    final key = '${widget.seasonId}:${episodes.length}:$nextId';
    if (_grid || nextId == null || _revealed == key) return;
    _revealed = key;
    final index = episodes.indexWhere((e) => e.id == nextId);
    if (index <= 0) return;
    final width = _itemWidth(context);
    final gap = _itemGap(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final target = (index * (width + gap) - gap * 2).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
    });
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.9).clamp(
          0.0,
          position.maxScrollExtent,
        );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final query = (
      userId: widget.userId,
      seriesId: widget.seriesId,
      seasonId: widget.seasonId,
    );
    final episodes = ref.watch(seriesEpisodesProvider(query));
    final ambient = WindowPosterBackgroundScope.isActive(context);
    final mobile = isMobileLayout(context);
    final values = episodes.value;
    final hasEpisodes = values != null && values.isNotEmpty;
    final count = values == null
        ? null
        : Text(
            l.libraryEpisodeCount(values.length),
            style: theme.typography.body.sm.copyWith(
              color: theme.colors.mutedForeground,
            ),
          );
    final header = mobile
        ? Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 12),
            child: Row(
              children: [
                Expanded(child: _SectionTitle(l.episodes)),
                if (hasEpisodes)
                  Semantics(
                    button: true,
                    label: _grid ? l.episodeRowView : l.episodeGridView,
                    child: GestureDetector(
                      key: const ValueKey('detail-episodes-toggle'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _grid = !_grid),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ?count,
                            const SizedBox(width: 4),
                            AnimatedRotation(
                              turns: _grid ? 0.25 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                FLucideIcons.chevronRight,
                                size: 18,
                                color: theme.colors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  ?count,
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [_SectionTitle(l.episodes), ?count],
                  ),
                ),
                if (hasEpisodes) ...[
                  if (!_grid) ...[
                    FButton.icon(
                      key: const ValueKey('detail-episodes-prev'),
                      variant: .ghost,
                      size: .sm,
                      semanticsLabel: l.back,
                      onPress: () => _page(-1),
                      child: const Icon(FLucideIcons.chevronLeft),
                    ),
                    const SizedBox(width: 2),
                    FButton.icon(
                      key: const ValueKey('detail-episodes-next'),
                      variant: .ghost,
                      size: .sm,
                      semanticsLabel: l.nextEpisode,
                      onPress: () => _page(1),
                      child: const Icon(FLucideIcons.chevronRight),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FButton.icon(
                    key: const ValueKey('detail-episodes-row-view'),
                    variant: _grid ? .ghost : .secondary,
                    size: .sm,
                    selected: !_grid,
                    semanticsLabel: l.episodeRowView,
                    onPress: () => setState(() => _grid = false),
                    child: const Icon(FLucideIcons.galleryHorizontal),
                  ),
                  const SizedBox(width: 2),
                  FButton.icon(
                    key: const ValueKey('detail-episodes-grid-view'),
                    variant: _grid ? .secondary : .ghost,
                    size: .sm,
                    selected: _grid,
                    semanticsLabel: l.episodeGridView,
                    onPress: () => setState(() => _grid = true),
                    child: const Icon(FLucideIcons.layoutGrid),
                  ),
                ],
              ],
            ),
          );
    final Widget body = episodes.when(
      data: (values) {
        if (values.isEmpty) {
          return EmptyNotice(l.noItems, translucent: ambient);
        }
        final nextId = resolveNextEpisode(values)?.episode.id;
        if (_grid) {
          final cards = [
            for (final episode in values)
              _EpisodeCard(item: episode, next: episode.id == nextId),
          ];
          return AdaptiveGrid(
            minWidth: mobile ? 136 : 260,
            maxColumns: 6,
            children: cards,
          );
        }
        _revealNext(values, nextId);
        final width = _itemWidth(context);
        final gap = _itemGap(context);
        final items = [
          for (final episode in values)
            mobile
                ? _EpisodeChip(item: episode, next: episode.id == nextId)
                : _EpisodeCard(item: episode, next: episode.id == nextId),
        ];
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: SingleChildScrollView(
            key: const ValueKey('detail-episodes-row'),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, item) in items.indexed) ...[
                  if (index > 0) SizedBox(width: gap),
                  SizedBox(width: width, child: item),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const LoadingNotice(),
      error: (error, _) => ErrorNotice(
        error,
        onRetry: () => ref.invalidate(seriesEpisodesProvider(query)),
      ),
    );
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: header),
        if (widget.tabs case final tabs?) SliverToBoxAdapter(child: tabs),
        SliverToBoxAdapter(child: body),
      ],
    );
  }
}

/// A compact numbered episode chip for the phone layout.
class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({required this.item, this.next = false});

  final MediaItem item;
  final bool next;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final colors = theme.colors;
    final ambient = WindowPosterBackgroundScope.isActive(context);
    final dark = colors.brightness == Brightness.dark;
    final progress = item.progressFraction;
    final number = item.indexNumber;
    final title = number == null
        ? item.name
        : context.l10n.episodeTitle(number, item.name);
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('detail-episode-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(playerLocation(item.id)),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            key: next ? ValueKey('detail-episode-next-${item.id}') : null,
            decoration: BoxDecoration(
              color: ambient
                  ? colors.card.withValues(alpha: dark ? 0.56 : 0.64)
                  : colors.muted,
              borderRadius: theme.style.borderRadius.md,
              border: next ? Border.all(color: colors.primary, width: 2) : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      number?.toString() ?? item.name,
                      key: ValueKey('detail-episode-number-${item.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.lg.copyWith(
                        fontWeight: FontWeight.w500,
                        color: item.played
                            ? colors.mutedForeground
                            : colors.foreground,
                      ),
                    ),
                  ),
                ),
                if (item.played)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(
                      FLucideIcons.check,
                      key: ValueKey('detail-episode-played-${item.id}'),
                      size: 12,
                      color: colors.mutedForeground,
                    ),
                  ),
                if (progress != null)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 8,
                    child: MediaProgressBar(value: progress),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 16:9 episode card with its runtime badge, watch state, and a two-line
/// synopsis, laid out for both the horizontal row and the grid.
class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({required this.item, this.next = false});

  final MediaItem item;

  /// Whether this is the episode the primary play action opens.
  final bool next;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _hovered = false;

  static String _clock(Duration duration) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(duration.inHours)}:${two(duration.inMinutes % 60)}:'
        '${two(duration.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final item = widget.item;
    final radius = theme.style.borderRadius.md;
    final progress = item.progressFraction;
    final duration = item.runtime;
    final overview = item.overview?.trim() ?? '';
    final title = item.indexNumber == null
        ? item.name
        : context.l10n.episodeTitle(item.indexNumber!, item.name);
    const badgeText = TextStyle(color: Color(0xFFFFFFFF));
    final thumbnail = AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaImage(
              url: item.poster?.url(),
              headers: item.poster?.headers ?? const {},
            ),
            AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: ColoredBox(
                color: const Color(0x33000000),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x80000000),
                    ),
                    child: const Icon(
                      FLucideIcons.play,
                      size: 22,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
            if (duration != null && duration > Duration.zero)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _clock(duration),
                    key: ValueKey('detail-episode-duration-${item.id}'),
                    style: theme.typography.body.xs.merge(badgeText),
                  ),
                ),
              ),
            if (item.played)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  key: ValueKey('detail-episode-played-${item.id}'),
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
            if (progress != null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: MediaProgressBar(value: progress),
              ),
            if (widget.next)
              DecoratedBox(
                key: ValueKey('detail-episode-next-${item.id}'),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colors.primary, width: 2),
                  borderRadius: radius,
                ),
              ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          key: ValueKey('detail-episode-${item.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => context.push(playerLocation(item.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              thumbnail,
              const SizedBox(height: 10),
              Text(
                title,
                key: ValueKey('detail-episode-title-${item.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.md.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  overview,
                  key: ValueKey('detail-episode-overview-${item.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
