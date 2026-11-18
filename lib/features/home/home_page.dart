import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/media_server/media_server_client.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_profile.dart';
import '../../data/media_server/server_repository.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/poster_background.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../detail/detail_page.dart';
import '../detail/played_status_button.dart';
import '../library/library_providers.dart';
import '../player/player_route.dart';
import 'home_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final servers = ref.watch(serversProvider);
    final content = PageScrollView(
      transparent: true,
      headerGap: 0,
      header: PageHeading(
        l.home,
        hideTitleOnMobile: true,
        action: FButton.icon(
          key: const ValueKey('home-refresh'),
          variant: .ghost,
          size: .sm,
          semanticsLabel: l.refresh,
          onPress: () => refreshHome(ref),
          child: const Icon(FLucideIcons.refreshCw),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: servers.when(
            data: (items) {
              if (items.isEmpty) {
                return EmptyNotice(
                  l.noServer,
                  child: FButton(
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => context.go('/settings?tab=servers'),
                    child: Text(l.addServer),
                  ),
                );
              }
              if (!ref
                  .watch(mediaServerClientProvider(items.first))
                  .isConfigured) {
                return EmptyNotice(
                  items.first.usesAccount ? l.serverLoginRequired : l.noApiKey,
                  child: FButton(
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => context.go('/settings?tab=servers'),
                    child: Text(l.servers),
                  ),
                );
              }
              final library = ref.watch(libraryViewsProvider);
              return library.when(
                data: (data) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PosterCarouselSection(client: data.client),
                    _MediaSection(
                      client: data.client,
                      title: l.continueWatching,
                      compact: true,
                      posterAction:
                          !data.client.server.type.supportsManualPlayed
                          ? null
                          : (item) => PlayedStatusButton(
                              key: ValueKey((
                                data.client.server,
                                data.userId,
                                item.id,
                              )),
                              client: data.client,
                              userId: data.userId,
                              item: item,
                              iconOnly: true,
                            ),
                      items: ref.watch(resumeItemsProvider),
                      onRetry: () => ref.invalidate(resumeItemsProvider),
                      onTap: (item, posterUrl) =>
                          _resume(context, item, posterUrl),
                    ),
                    if (data.client.server.type.supportsRecentlyAdded)
                      _MediaSection(
                        client: data.client,
                        title: l.recentlyAdded,
                        showEmpty:
                            data.client.server.type == MediaServerType.ugreen,
                        items: ref.watch(latestItemsProvider),
                        onRetry: () => ref.invalidate(latestItemsProvider),
                        onTap: (item, posterUrl) =>
                            _openDetail(context, item, posterUrl),
                      ),
                  ],
                ),
                loading: () => const LoadingNotice(),
                error: (error, _) => ErrorNotice(
                  error,
                  onRetry: () => ref.invalidate(libraryViewsProvider),
                ),
              );
            },
            loading: () => const LoadingNotice(),
            error: (error, _) => ErrorNotice(
              error,
              onRetry: () => ref.invalidate(serversProvider),
            ),
          ),
        ),
      ],
    );
    if (WindowPosterBackgroundScope.hasHost(context)) return content;
    final background = watchHomePosterBackground(ref);
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

/// Resumes playback where the user left off; series open their detail page.
void _resume(BuildContext context, MediaItem item, String? posterUrl) {
  if (item.isSeries) {
    _openDetail(context, item, posterUrl);
  } else {
    context.push(playerLocation(item.id));
  }
}

void _openDetail(BuildContext context, MediaItem item, String? posterUrl) {
  if (item.isEpisode) {
    context.push(playerLocation(item.id));
    return;
  }
  context.go(
    '/library/${item.id}',
    extra: DetailRouteExtra(item: item, posterUrl: posterUrl),
  );
}

class _PosterCarouselSection extends ConsumerWidget {
  const _PosterCarouselSection({required this.client});

  final MediaServerClient client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(randomItemsProvider);
    final height = isMobileLayout(context) ? 216.0 : 400.0;
    return items.when(
      data: (values) => values.isEmpty
          ? const SizedBox.shrink()
          : _PosterCarousel(client: client, items: values, height: height),
      loading: () => SizedBox(
        height: height,
        child: const Surface(child: Center(child: FCircularProgress())),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _PosterCarousel extends ConsumerStatefulWidget {
  const _PosterCarousel({
    required this.client,
    required this.items,
    required this.height,
  });

  static const autoPlayInterval = Duration(seconds: 6);
  static const _slideDuration = Duration(milliseconds: 420);

  final MediaServerClient client;
  final List<MediaItem> items;
  final double height;

  @override
  ConsumerState<_PosterCarousel> createState() => _PosterCarouselState();
}

class _PosterCarouselState extends ConsumerState<_PosterCarousel> {
  late PageController _pageController;
  Timer? _autoPlayTimer;
  bool _hovered = false;
  bool _tickerEnabled = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final initial = ref
        .read(homeCarouselIndexProvider)
        .clamp(0, widget.items.length - 1);
    _pageController = PageController(
      initialPage: widget.items.length > 1 ? initial + 1 : 0,
      keepPage: false,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncAutoPlay();
  }

  @override
  void didUpdateWidget(covariant _PosterCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      final clamped = ref
          .read(homeCarouselIndexProvider)
          .clamp(0, widget.items.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(widget.items.length > 1 ? clamped + 1 : 0);
        ref.read(homeCarouselIndexProvider.notifier).set(clamped);
      });
      _syncAutoPlay();
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _syncAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    if (!mounted ||
        widget.items.length <= 1 ||
        !_tickerEnabled ||
        _reduceMotion ||
        _hovered) {
      return;
    }
    _autoPlayTimer = Timer.periodic(_PosterCarousel.autoPlayInterval, (_) {
      if (!mounted || !_pageController.hasClients || widget.items.length <= 1) {
        return;
      }
      _moveBy(1);
    });
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    _hovered = value;
    _syncAutoPlay();
  }

  int _itemIndex(int page) =>
      widget.items.length > 1 ? (page - 1) % widget.items.length : 0;

  // The extra pages repeat the last and first items. Once scrolling stops,
  // move to the identical real page without a visible transition.
  void _normalizePage() {
    if (!_pageController.hasClients || widget.items.length <= 1) return;
    final page = _pageController.page;
    if (page == 0) {
      _pageController.jumpToPage(widget.items.length);
    } else if (page == widget.items.length + 1) {
      _pageController.jumpToPage(1);
    }
  }

  void _moveBy(int delta) {
    if (!_pageController.hasClients ||
        _pageController.position.isScrollingNotifier.value) {
      return;
    }
    _normalizePage();
    _goToPage(_pageController.page!.round() + delta);
  }

  void _goToPage(int page) {
    final target = page.clamp(0, widget.items.length + 1);
    if (_pageController.hasClients) {
      if (_reduceMotion) {
        _pageController.jumpToPage(target);
      } else {
        unawaited(
          _pageController.animateToPage(
            target,
            duration: _PosterCarousel._slideDuration,
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    _syncAutoPlay();
  }

  void _handlePageChanged(int index) {
    ref.read(homeCarouselIndexProvider.notifier).set(_itemIndex(index));
    _syncAutoPlay();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final mobile = isMobileLayout(context);
    final length = widget.items.length;
    final activeIndex = ref
        .watch(homeCarouselIndexProvider)
        .clamp(0, length - 1);
    final radius = theme.style.borderRadius.lg;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: SizedBox(
        key: const ValueKey('home-poster-carousel'),
        height: widget.height,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: NotificationListener<ScrollEndNotification>(
                  onNotification: (notification) {
                    if (notification.depth == 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            _pageController.hasClients &&
                            !_pageController
                                .position
                                .isScrollingNotifier
                                .value) {
                          _normalizePage();
                        }
                      });
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: length > 1 ? length + 2 : 1,
                    onPageChanged: _handlePageChanged,
                    itemBuilder: (context, index) => _CarouselSlide(
                      client: widget.client,
                      item: widget.items[_itemIndex(index)],
                      mobile: mobile,
                      hasMultiple: length > 1,
                    ),
                  ),
                ),
              ),
              if (length > 1) ...[
                Positioned(
                  top: mobile ? 10 : 16,
                  right: mobile ? 10 : 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CarouselArrowButton(
                        key: const ValueKey('home-carousel-prev'),
                        icon: FLucideIcons.chevronLeft,
                        onTap: () => _moveBy(-1),
                      ),
                      const SizedBox(width: 8),
                      _CarouselArrowButton(
                        key: const ValueKey('home-carousel-next'),
                        icon: FLucideIcons.chevronRight,
                        onTap: () => _moveBy(1),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: mobile ? 14 : 24,
                  bottom: mobile ? 12 : 20,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < length; i++)
                        GestureDetector(
                          key: ValueKey('home-carousel-dot-$i'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _goToPage(i + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 4,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              width: i == activeIndex ? 18 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == activeIndex
                                    ? const Color(0xFFFFFFFF)
                                    : const Color(0x66FFFFFF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: const Color(0x24FFFFFF),
                      width: theme.style.borderWidth,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselArrowButton extends StatelessWidget {
  const _CarouselArrowButton({
    required this.icon,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0x59000000),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFFFFFFFF)),
      ),
    ),
  );
}

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({
    required this.client,
    required this.item,
    required this.mobile,
    required this.hasMultiple,
  });

  final MediaServerClient client;
  final MediaItem item;
  final bool mobile;
  final bool hasMultiple;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final posterUrl = item.poster?.url();
    final backdropUrl = item.backdrop?.url(width: 1920);
    final overview = item.overview?.trim() ?? '';
    final pad = mobile ? 14.0 : 24.0;
    final posterWidth = mobile ? 80.0 : 160.0;
    final tags = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (item.officialRating != null && item.officialRating!.isNotEmpty)
        item.officialRating!,
      ...item.genres.take(3),
    ];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('home-carousel-slide-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetail(context, item, posterUrl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdropUrl != null)
              MediaImage(
                url: backdropUrl,
                headers: item.backdrop?.headers ?? const {},
              )
            else if (posterUrl != null)
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 24,
                    sigmaY: 24,
                    tileMode: TileMode.clamp,
                  ),
                  child: Transform.scale(
                    scale: 1.15,
                    child: MediaImage(
                      url: posterUrl,
                      headers: item.poster?.headers ?? const {},
                    ),
                  ),
                ),
              )
            else
              const MediaPlaceholder(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x1F000000),
                    Color(0x73000000),
                    Color(0xE6000000),
                  ],
                  stops: [0.0, 0.48, 1.0],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0x8C000000), Color(0x00000000)],
                  stops: [0.0, 0.65],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                pad,
                hasMultiple && !mobile ? pad + 112 : pad,
                hasMultiple && mobile ? pad + 18 : pad,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: posterWidth,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: theme.style.borderRadius.md,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: theme.style.borderRadius.md,
                            child: MediaImage(
                              url: posterUrl,
                              headers: item.poster?.headers ?? const {},
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: mobile ? 12 : 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayTitle,
                            maxLines: mobile ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (mobile
                                        ? theme.typography.display.md
                                        : theme.typography.display.xl)
                                    .copyWith(
                                      color: const Color(0xFFFFFFFF),
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final tag in tags) _CarouselTag(text: tag),
                              ],
                            ),
                          ],
                          if (!mobile && overview.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Flexible(
                              child: Text(
                                overview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.typography.body.sm.copyWith(
                                  color: const Color(0xCCFFFFFF),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselTag extends StatelessWidget {
  const _CarouselTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0x33FFFFFF),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: context.theme.typography.body.xs.copyWith(
        color: const Color(0xEBFFFFFF),
      ),
    ),
  );
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.client,
    required this.title,
    required this.items,
    required this.onRetry,
    required this.onTap,
    this.compact = false,
    this.showEmpty = false,
    this.posterAction,
  });

  final MediaServerClient client;
  final String title;
  final AsyncValue<List<MediaItem>> items;
  final VoidCallback onRetry;
  final void Function(MediaItem item, String? posterUrl) onTap;
  final bool compact;
  final bool showEmpty;
  final Widget Function(MediaItem item)? posterAction;

  @override
  Widget build(BuildContext context) {
    return items.when(
      data: (values) {
        if (values.isEmpty) {
          return showEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: EmptyNotice(context.l10n.noItems),
                )
              : const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    ...ScrollConfiguration.of(context).dragDevices,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < values.length; index++) ...[
                        if (index > 0) const SizedBox(width: 12),
                        Builder(
                          builder: (context) {
                            final item = values[index];
                            final aspectRatio = compact ? 16 / 9 : 2 / 3;
                            return SizedBox(
                              width: compact ? 220 : 160,
                              child: MediaPosterCard(
                                client: client,
                                item: item,
                                progress: item.progressFraction,
                                posterAction: posterAction?.call(item),
                                aspectRatio: aspectRatio,
                                reserveMetadataSpace: true,
                                posterOverride: compact
                                    ? null
                                    : item.seriesPoster,
                                onPosterTap: (posterUrl) =>
                                    onTap(item, posterUrl),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 28),
        child: LoadingNotice(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: ErrorNotice(error, onRetry: onRetry),
      ),
    );
  }
}
