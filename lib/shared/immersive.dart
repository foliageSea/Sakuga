import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

/// Whether the immersive page has scrolled its artwork away from under the
/// window chrome, so the chrome needs its own frosted backing.
final immersiveScrolledProvider = NotifierProvider.autoDispose
    .family<ImmersiveScrolled, bool, String>(ImmersiveScrolled.new);

class ImmersiveScrolled extends Notifier<bool> {
  ImmersiveScrolled(String route);
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

/// Tells a page that the shell lays its chrome (desktop title bar or phone
/// header) over the page, so artwork can extend underneath it.
class ImmersiveScope extends InheritedWidget {
  const ImmersiveScope({
    required this.active,
    required this.topInset,
    required super.child,
    super.key,
  });

  /// Whether the chrome currently overlays the page.
  final bool active;

  /// Height of the overlaid chrome the page should keep content clear of.
  final double topInset;

  static ImmersiveScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImmersiveScope>();

  /// The overlaid chrome height, or null when the page is not immersive.
  static double? insetOf(BuildContext context) {
    final scope = maybeOf(context);
    return scope != null && scope.active ? scope.topInset : null;
  }

  @override
  bool updateShouldNotify(ImmersiveScope oldWidget) =>
      active != oldWidget.active || topInset != oldWidget.topInset;
}

/// Window chrome drawn over immersive artwork: light-on-dark while the
/// artwork is underneath, then a frosted bar in the regular theme once the
/// page scrolls content beneath it.
class ImmersiveChrome extends ConsumerWidget {
  const ImmersiveChrome({
    required this.route,
    required this.overArtworkTheme,
    required this.child,
    super.key,
  });

  final String route;

  /// Theme used while the chrome sits on top of the artwork.
  final FThemeData overArtworkTheme;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrolled = ref.watch(immersiveScrolledProvider(route));
    final theme = context.theme;
    final colors = theme.colors;
    final dark = colors.brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              key: const ValueKey('immersive-chrome-backing'),
              opacity: scrolled ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background.withValues(alpha: 0.72),
                      border: Border(
                        bottom: BorderSide(
                          color: dark
                              ? colors.border
                              : colors.foreground.withValues(alpha: 0.09),
                          width: theme.style.borderWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        FTheme(data: scrolled ? theme : overArtworkTheme, child: child),
      ],
    );
  }
}
