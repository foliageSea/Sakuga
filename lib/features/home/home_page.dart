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
import '../../shared/immersive.dart';
import '../../shared/localization.dart';
import '../../shared/media_preview_card.dart';
import '../../shared/media_widgets.dart';
import '../../shared/poster_background.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../detail/detail_page.dart';
import '../detail/media_header.dart';
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
    // The shell overlays its chrome while the carousel artwork extends under
    // it; the chrome then hosts the refresh action instead of a page heading.
    final immersive = ImmersiveScope.insetOf(context) != null;
    final content = PageScrollView(
      scrollbars: false,
      transparent: true,
      headerGap: 0,
      flushTop: immersive,
      maxWidth: double.infinity,
      header: immersive
          ? null
          : PageHeading(
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
                      title: l.continueWatching,
                      resumesPlayback: true,
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
                      onTap: (item) =>
                          _resume(context, item, item.poster?.url()),
                    ),
                    if (data.client.server.type.supportsRecentlyAdded)
                      _MediaSection(
                        title: l.recentlyAdded,
                        showEmpty:
                            data.client.server.type == MediaServerType.ugreen,
                        items: ref.watch(latestItemsProvider),
                        onRetry: () => ref.invalidate(latestItemsProvider),
                        onTap: (item) => _openDetail(
                          context,
                          item,
                          (item.seriesPoster ?? item.poster)?.url(),
                        ),
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
    final inset = ImmersiveScope.insetOf(context);
    final height =
        headerArtworkHeight(context) + (isMobileLayout(context) ? 60.0 : 0.0);
    return items.when(
      data: (values) => values.isEmpty
          ? const SizedBox.shrink()
          : _PosterCarousel(
              client: client,
              items: values,
              height: height,
              immersiveInset: inset,
            ),
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
    this.immersiveInset,
  });

  static const autoPlayInterval = Duration(seconds: 6);
  static const _slideDuration = Duration(milliseconds: 420);

  final MediaServerClient client;
  final List<MediaItem> items;
  final double height;

  /// Height of the window chrome overlaid on the artwork, when immersive.
  final double? immersiveInset;

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
    final dotColor = mobile ? theme.colors.foreground : const Color(0xFFFFFFFF);
    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < length; i++)
          GestureDetector(
            key: ValueKey('home-carousel-dot-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _goToPage(i + 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: i == activeIndex ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == activeIndex
                      ? dotColor
                      : dotColor.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
      ],
    );
    final pages = ScrollConfiguration(
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
                  !_pageController.position.isScrollingNotifier.value) {
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
            immersiveInset: widget.immersiveInset,
          ),
        ),
      ),
    );

    if (mobile) {
      // Phones: edge-to-edge like the detail header, so the artwork bleeds
      // past the page padding and fades into the page.
      final bleed = pagePadding(context);
      return SizedBox(
        key: const ValueKey('home-poster-carousel'),
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth + bleed * 2;
            return OverflowBox(
              minWidth: width,
              maxWidth: width,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  pages,
                  if (length > 1)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Center(child: dots),
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    if (widget.immersiveInset != null) {
      // Edge-to-edge under the title bar, fading into the page below.
      final bleed = pagePadding(context);
      return MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: SizedBox(
          key: const ValueKey('home-poster-carousel'),
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth + bleed * 2;
              return OverflowBox(
                minWidth: width,
                maxWidth: width,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    pages,
                    if (length > 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Center(child: dots),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

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
              pages,
              if (length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Center(child: dots),
                ),
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

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({
    required this.client,
    required this.item,
    required this.mobile,
    required this.hasMultiple,
    this.immersiveInset,
  });

  final MediaServerClient client;
  final MediaItem item;
  final bool mobile;
  final bool hasMultiple;
  final double? immersiveInset;

  /// Darkens the top of artwork that sits under window chrome so its light
  /// controls stay legible.
  Widget _chromeScrim(double inset) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    height: inset * 2.5,
    child: const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x8C000000), Color(0x00000000)],
          ),
        ),
      ),
    ),
  );

  Widget _artwork() {
    final backdrop = item.backdrop;
    final poster = item.poster;
    if (backdrop != null) {
      return MediaImage(
        url: backdrop.url(width: 1920),
        headers: backdrop.headers,
      );
    }
    if (poster == null) return const MediaPlaceholder();
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: 24,
          sigmaY: 24,
          tileMode: TileMode.clamp,
        ),
        child: Transform.scale(
          scale: 1.15,
          child: MediaImage(url: poster.url(), headers: poster.headers),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posterUrl = item.poster?.url();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('home-carousel-slide-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetail(context, item, posterUrl),
        child: mobile ? _mobile(context) : _wide(context),
      ),
    );
  }

  /// Phone slide: faded edge-to-edge artwork with centered title art and
  /// facts, mirroring the phone detail header.
  Widget _mobile(BuildContext context) {
    final bleed = pagePadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('home-carousel-mobile-art'),
          height: headerArtworkHeight(context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                  stops: [0.55, 1],
                ).createShader(bounds),
                child: _artwork(),
              ),
              if (immersiveInset case final inset?) _chromeScrim(inset),
              Positioned(
                left: bleed,
                right: bleed,
                bottom: 0,
                child: MediaTitleArt(
                  item: item,
                  onDark: false,
                  center: true,
                  keyPrefix: 'home-carousel-${item.id}',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: bleed),
          child: MediaMetaRow(item: item, onDark: false, center: true),
        ),
      ],
    );
  }

  /// Wide slide: the detail banner with poster, title art, facts and synopsis.
  Widget _wide(BuildContext context) {
    final theme = context.theme;
    final overview = item.overview?.trim() ?? '';
    final overviewStyle = theme.typography.body.md.copyWith(
      color: const Color(0xE6FFFFFF),
      height: 1.6,
    );
    final inset = immersiveInset;
    final side = inset == null ? 32.0 : pagePadding(context);
    final slide = Stack(
      fit: StackFit.expand,
      children: [
        _artwork(),
        ?(inset == null ? null : _chromeScrim(inset)),
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
        Positioned(
          left: side,
          right: side,
          bottom: hasMultiple ? 40 : 28,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 150,
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
                        url: item.poster?.url(),
                        headers: item.poster?.headers ?? const {},
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final title = MediaTitleArt(
                      item: item,
                      onDark: true,
                      keyPrefix: 'home-carousel-${item.id}',
                    );
                    Widget synopsis(int lines) => Text(
                      overview,
                      maxLines: lines,
                      overflow: TextOverflow.ellipsis,
                      style: overviewStyle,
                    );
                    if (constraints.maxWidth < 720) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const SizedBox(height: 12),
                          MediaMetaRow(item: item, onDark: true),
                          if (overview.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            synopsis(2),
                          ],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 320,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: title,
                          ),
                        ),
                        const SizedBox(width: 40),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MediaMetaRow(item: item, onDark: true),
                              if (overview.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                synopsis(3),
                              ],
                            ],
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
    );
    if (inset == null) return slide;
    // Fade the bottom edge into the page instead of ending on a hard line.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: [0.88, 1],
      ).createShader(bounds),
      child: slide,
    );
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.title,
    required this.items,
    required this.onRetry,
    required this.onTap,
    this.resumesPlayback = false,
    this.showEmpty = false,
    this.posterAction,
  });

  final String title;
  final AsyncValue<List<MediaItem>> items;
  final VoidCallback onRetry;
  final ValueChanged<MediaItem> onTap;
  final bool resumesPlayback;
  final bool showEmpty;
  final Widget Function(MediaItem item)? posterAction;

  String _previewTitle(MediaItem item) {
    final title = item.displayTitle;
    final episode = item.displaySubtitle;
    return episode == null || episode == title ? title : '$title · $episode';
  }

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, item) in values.indexed) ...[
                        if (index > 0) const SizedBox(width: 12),
                        SizedBox(
                          width: resumesPlayback ? 220 : 160,
                          child: MediaPreviewCard(
                            item: item,
                            title: _previewTitle(item),
                            overview: '',
                            aspectRatio: resumesPlayback ? 16 / 9 : 2 / 3,
                            artwork: resumesPlayback
                                ? item.poster
                                : item.seriesPoster,
                            posterAction: posterAction?.call(item),
                            playOnTap:
                                item.isEpisode ||
                                (resumesPlayback && !item.isSeries),
                            onTap: () => onTap(item),
                          ),
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
