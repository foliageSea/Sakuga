import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/images/artwork_cache.dart';

/// Remote poster artwork used for the ambient window background on home and
/// detail views.
@immutable
class PosterBackground {
  const PosterBackground({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosterBackground &&
          url == other.url &&
          mapEquals(headers, other.headers);

  @override
  int get hashCode => Object.hash(
    url,
    Object.hashAllUnordered(
      headers.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// Marks a subtree whose ancestor window shell owns a [PosterWindowBackground],
/// and exposes whether an ambient poster background is currently active.
class WindowPosterBackgroundScope extends InheritedWidget {
  const WindowPosterBackgroundScope({
    required this.active,
    this.shellHosted = false,
    required super.child,
    super.key,
  });

  final bool active;
  final bool shellHosted;

  /// Whether an ancestor paints a [PosterWindowBackground].
  static bool hasHost(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WindowPosterBackgroundScope>() !=
      null;

  /// Whether the enclosing [AppShell] owns the mobile header and window
  /// background.
  static bool hasShell(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WindowPosterBackgroundScope>()
          ?.shellHosted ??
      false;

  /// Whether an ambient poster background is currently displayed.
  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WindowPosterBackgroundScope>()
          ?.active ??
      false;

  @override
  bool updateShouldNotify(WindowPosterBackgroundScope oldWidget) =>
      active != oldWidget.active || shellHosted != oldWidget.shellHosted;
}

/// Full-window ambient background: renders [background] stretched across the
/// viewport behind a Gaussian blur scrim so foreground chrome and text stay
/// legible in both light and dark themes.
class PosterWindowBackground extends StatefulWidget {
  const PosterWindowBackground({
    required this.background,
    this.blurSigma = 20,
    this.titleBarBlurSigma = 64,
    this.sidebarBlurSigma = 64,
    this.titleBarHeight = 0,
    this.sidebarWidth = 0,
    this.routeRadius = Radius.zero,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 260),
    super.key,
  });

  final PosterBackground? background;

  /// Route content blur, independent of the desktop chrome.
  final double blurSigma;
  final double titleBarBlurSigma;
  final double sidebarBlurSigma;
  final double titleBarHeight;
  final double sidebarWidth;
  final Radius routeRadius;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  @override
  State<PosterWindowBackground> createState() => _PosterWindowBackgroundState();
}

class _PosterWindowBackgroundState extends State<PosterWindowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.fadeInDuration,
    reverseDuration: widget.fadeOutDuration,
    value: widget.background == null ? 0 : 1,
  )..addStatusListener(_handleStatus);

  late final CurvedAnimation _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  late PosterBackground? _current = widget.background;
  PosterBackground? _outgoing;
  bool _currentReady = false;
  bool _reduceMotion = false;
  Timer? _outgoingReleaseTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(covariant PosterWindowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fadeInDuration != widget.fadeInDuration) {
      _controller.duration = widget.fadeInDuration;
    }
    if (oldWidget.fadeOutDuration != widget.fadeOutDuration) {
      _controller.reverseDuration = widget.fadeOutDuration;
    }
    final next = widget.background;
    if (next == oldWidget.background) return;
    _outgoingReleaseTimer?.cancel();
    _outgoingReleaseTimer = null;

    if (next == null) {
      _outgoing = null;
      _currentReady = false;
      if (_reduceMotion || _current == null) {
        _current = null;
        _controller.value = 0;
      } else {
        _controller.reverse();
      }
      return;
    }

    if (_reduceMotion) {
      _outgoing = null;
      _current = next;
      _currentReady = true;
      _controller.value = 1;
    } else if (_current?.url == next.url) {
      _outgoing = null;
      _current = next;
      _controller.forward();
    } else {
      _outgoing = _controller.value > 0 ? _current : null;
      _current = next;
      _currentReady = false;
      _controller.forward(from: 0);
    }
  }

  void _markCurrentReady(String url) {
    if (_current?.url != url || _currentReady) return;
    _currentReady = true;
    if (_outgoing == null || !_controller.isCompleted) return;
    _scheduleClearOutgoing();
  }

  void _scheduleClearOutgoing() {
    if (_outgoingReleaseTimer != null || _outgoing == null) return;
    if (_reduceMotion) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _outgoing != null) {
          setState(() => _outgoing = null);
        }
      });
      return;
    }
    // imageBuilder reports the first frame before the image's 200ms fade-in
    // finishes. Keep the previous artwork through that inner transition, even
    // when the outer animation has already completed.
    _outgoingReleaseTimer = Timer(const Duration(milliseconds: 220), () {
      _outgoingReleaseTimer = null;
      if (mounted && _outgoing != null) {
        setState(() => _outgoing = null);
      }
    });
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.background == null) {
      if (_current != null || _outgoing != null) {
        setState(() {
          _current = null;
          _outgoing = null;
          _currentReady = false;
        });
      }
    } else if (status == AnimationStatus.completed &&
        _outgoing != null &&
        _currentReady) {
      _scheduleClearOutgoing();
    }
  }

  @override
  void dispose() {
    _outgoingReleaseTimer?.cancel();
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final current = _current;
    if (current == null) {
      return ColoredBox(
        key: const ValueKey('window-poster-background'),
        color: colors.background,
      );
    }
    final dark = colors.brightness == Brightness.dark;
    return RepaintBoundary(
      key: const ValueKey('window-poster-background'),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.background),
            if (_outgoing case final outgoing?)
              _PosterArtworkLayer(
                key: ValueKey(('outgoing', outgoing.url)),
                background: outgoing,
              ),
            FadeTransition(
              opacity: _animation,
              child: _PosterArtworkLayer(
                key: ValueKey(current.url),
                background: current,
                onSettled: () => _markCurrentReady(current.url),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final routeRect = Rect.fromLTRB(
                  widget.sidebarWidth,
                  widget.titleBarHeight,
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                // All regions sample the same artwork without compounding blur.
                return BackdropGroup(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final (region, sigma, key) in [
                        if (widget.titleBarHeight > 0)
                          (
                            _PosterRegion.titleBar,
                            widget.titleBarBlurSigma,
                            'window-poster-title-bar-blur-mask',
                          ),
                        if (widget.sidebarWidth > 0)
                          (
                            _PosterRegion.sidebar,
                            widget.sidebarBlurSigma,
                            'window-poster-sidebar-blur-mask',
                          ),
                        (
                          _PosterRegion.route,
                          widget.blurSigma,
                          'window-poster-blur-mask',
                        ),
                      ])
                        ClipPath(
                          clipper: _PosterRegionClipper(
                            region: region,
                            routeRect: routeRect,
                            radius: widget.routeRadius,
                          ),
                          child: BackdropFilter.grouped(
                            key: ValueKey(key),
                            filter: ImageFilter.blur(
                              sigmaX: sigma,
                              sigmaY: sigma,
                              tileMode: TileMode.clamp,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    colors.background.withValues(
                                      alpha: dark ? 0.62 : 0.64,
                                    ),
                                    colors.background.withValues(alpha: 0.78),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

enum _PosterRegion { titleBar, sidebar, route }

class _PosterRegionClipper extends CustomClipper<Path> {
  const _PosterRegionClipper({
    required this.region,
    required this.routeRect,
    required this.radius,
  });

  final _PosterRegion region;
  final Rect routeRect;
  final Radius radius;

  @override
  Path getClip(Size size) {
    final route = Path()
      ..addRRect(RRect.fromRectAndCorners(routeRect, topLeft: radius));
    return switch (region) {
      _PosterRegion.titleBar =>
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, routeRect.top)),
      // Include the route's outer corner so no unfiltered artwork shows through.
      _PosterRegion.sidebar => Path.combine(
        PathOperation.difference,
        Path()
          ..addRect(Rect.fromLTRB(0, routeRect.top, size.width, size.height)),
        route,
      ),
      _PosterRegion.route => route,
    };
  }

  @override
  bool shouldReclip(_PosterRegionClipper oldClipper) =>
      region != oldClipper.region ||
      routeRect != oldClipper.routeRect ||
      radius != oldClipper.radius;
}

class _PosterArtworkLayer extends StatelessWidget {
  const _PosterArtworkLayer({
    required this.background,
    this.onSettled,
    super.key,
  });

  final PosterBackground background;
  final VoidCallback? onSettled;

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: 1.1,
    child: CachedNetworkImage(
      imageUrl: background.url,
      httpHeaders: background.headers,
      cacheKey: artworkCacheKey(background.url, background.headers),
      cacheManager: ArtworkCacheManager.instance,
      fit: BoxFit.cover,
      useOldImageOnUrlChange: true,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      imageBuilder: (context, imageProvider) {
        onSettled?.call();
        return Image(image: imageProvider, fit: BoxFit.cover);
      },
      placeholder: (_, _) => const SizedBox.expand(),
      errorWidget: (_, _, _) {
        onSettled?.call();
        return const SizedBox.expand();
      },
    ),
  );
}
