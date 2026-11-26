import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:forui/forui.dart';

import '../core/settings/settings.dart';
import '../core/window/desktop_window.dart';
import '../data/media_server/media_server_factory.dart';
import '../features/detail/detail_page.dart';
import '../features/home/home_providers.dart';
import '../features/library/library_providers.dart';
import '../features/library/library_server_picker.dart';
import '../shared/language_options.dart';
import '../shared/immersive.dart';
import '../shared/localization.dart';
import '../shared/poster_background.dart';
import '../shared/widgets.dart';
import 'theme.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    required this.shell,
    this.backLocation,
    this.isHomeRoute = false,
    this.isLibraryRootRoute = false,
    this.detailBackgroundSpec,
    super.key,
  });
  final StatefulNavigationShell shell;
  final String? backLocation;
  final bool isHomeRoute;
  final bool isLibraryRootRoute;
  final DetailBackgroundSpec? detailBackgroundSpec;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(desktopWindowProvider);
    final settings = ref.watch(settingsProvider);
    final posterBackground = detailBackgroundSpec != null
        ? watchDetailPosterBackground(ref, detailBackgroundSpec)
        : isHomeRoute || isLibraryRootRoute
        ? watchHomePosterBackground(ref)
        : null;
    final activeServer = isLibraryRootRoute || isHomeRoute
        ? ref.watch(activeServerProvider)
        : null;
    final serverConfigured =
        activeServer != null &&
        ref.watch(mediaServerClientProvider(activeServer)).isConfigured;
    final canRefreshLibrary = isLibraryRootRoute && serverConfigured;
    final canRefreshHome = isHomeRoute && serverConfigured;
    final immersive = isHomeRoute && posterBackground != null;
    final overArtworkTheme = ref.watch(appThemesProvider).dark;
    final l = context.l10n;
    final labels = [l.home, l.library, l.settings];
    const icons = [
      FLucideIcons.house,
      FLucideIcons.film,
      FLucideIcons.settings2,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < mobileBreakpoint;
        final compact = constraints.maxWidth < 1024 || settings.compactSidebar;
        final sidebarWidth = mobile ? 0.0 : (compact ? 76.0 : 200.0);
        final theme = context.theme;
        final colors = theme.colors;
        final dark = colors.brightness == Brightness.dark;
        final dividerColor = dark
            ? colors.border
            : colors.foreground.withValues(alpha: 0.09);
        final sidebarActiveFill = colors.foreground.withValues(
          alpha: dark ? 0.115 : 0.045,
        );
        final showTitleBar = window.available && !window.fullScreen;
        // The home carousel artwork extends under the window chrome: the
        // desktop title bar, or the phone header and status bar.
        final immersiveDesktop = immersive && !mobile && showTitleBar;
        final immersiveMobile = immersive && mobile && backLocation == null;
        final refreshHomeButton = FButton.icon(
          key: const ValueKey('home-refresh'),
          variant: .ghost,
          size: .sm,
          semanticsLabel: l.refresh,
          onPress: () => refreshHome(ref),
          child: const Icon(FLucideIcons.refreshCw),
        );
        final Widget? titleBar = showTitleBar
            ? DesktopTitleBar(
                homeAction: immersiveDesktop && canRefreshHome
                    ? refreshHomeButton
                    : null,
                controller: window,
                libraryServerAction: const LibraryServerAction(compact: true),
                compactSidebar: settings.compactSidebar,
                onToggleCompactSidebar: () async {
                  try {
                    await ref
                        .read(settingsProvider.notifier)
                        .update(
                          (value) => value.copyWith(
                            compactSidebar: !value.compactSidebar,
                          ),
                        );
                  } catch (error) {
                    if (context.mounted) {
                      notifyUser(context, failureMessage(context, error));
                    }
                  }
                },
                language: settings.language,
                onLanguageChanged: (language) => _update(
                  context,
                  ref,
                  (value) => value.copyWith(language: language),
                ),
                onToggleTheme: () => _update(
                  context,
                  ref,
                  (value) => value.copyWith(
                    themeMode:
                        context.theme.colors.brightness == Brightness.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  ),
                ),
              )
            : null;
        final Widget mobileHeader = Builder(
          builder: (headerContext) {
            final pad = pagePadding(headerContext);
            return FHeader(
              key: const ValueKey('mobile-header'),
              style: .delta(
                padding: .value(EdgeInsets.fromLTRB(pad, 8, pad, 10)),
              ),
              title: Row(
                children: [
                  if (detailBackgroundSpec != null) ...[
                    FButton.icon(
                      key: const ValueKey('detail-back'),
                      variant: .ghost,
                      size: .sm,
                      semanticsLabel: l.back,
                      onPress: () => popDetailRoute(headerContext),
                      child: const Icon(FLucideIcons.arrowLeft),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: detailBackgroundSpec != null
                        ? DetailHeaderTitle(spec: detailBackgroundSpec!)
                        : _HeaderTitle(labels[shell.currentIndex]),
                  ),
                ],
              ),
              suffixes: [
                if (!window.available || window.fullScreen)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 160),
                    child: const LibraryServerAction(compact: true),
                  ),
                if (canRefreshLibrary || canRefreshHome)
                  FButton.icon(
                    key: ValueKey(
                      canRefreshHome ? 'home-refresh' : 'library-refresh',
                    ),
                    variant: .ghost,
                    size: .sm,
                    semanticsLabel: l.refresh,
                    onPress: () {
                      if (canRefreshHome) {
                        refreshHome(ref);
                      } else {
                        ref.invalidate(libraryViewsProvider);
                      }
                    },
                    child: const Icon(FLucideIcons.refreshCw),
                  ),
              ],
            );
          },
        );
        return ListenableBuilder(
          listenable: window,
          builder: (context, _) => WindowPosterBackgroundScope(
            active: posterBackground != null,
            shellHosted: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterWindowBackground(
                  background: posterBackground,
                  blurSigma: 20,
                  titleBarBlurSigma: 64,
                  sidebarBlurSigma: 64,
                  titleBarHeight: window.available && !window.fullScreen
                      ? 48
                      : 0,
                  sidebarWidth: sidebarWidth,
                  routeRadius: mobile
                      ? Radius.zero
                      : theme.style.borderRadius.lg.topLeft,
                ),
                SafeArea(
                  top: !window.available && !immersiveMobile,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          if (titleBar != null && !immersiveDesktop) titleBar,
                          Expanded(
                            child: Row(
                              children: [
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: sidebarWidth,
                                    child: mobile
                                        ? null
                                        : Padding(
                                            padding: EdgeInsets.only(
                                              top: immersiveDesktop ? 48 : 0,
                                            ),
                                            child: FSidebar(
                                              style: .delta(
                                                decoration: .boxDelta(
                                                  color: null,
                                                  border: const Border(),
                                                ),
                                                groupStyle: .delta(
                                                  itemStyle: .delta(
                                                    backgroundColor: FVariants(
                                                      const Color(0x00000000),
                                                      variants: {
                                                        [
                                                          .selected,
                                                          .hovered,
                                                          .pressed,
                                                        ]: sidebarActiveFill,
                                                        [
                                                          .disabled,
                                                        ]: const Color(
                                                          0x00000000,
                                                        ),
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                constraints:
                                                    BoxConstraints.tightFor(
                                                      width: sidebarWidth,
                                                    ),
                                              ),
                                              header: SizedBox(
                                                width: double.infinity,
                                                child: Padding(
                                                  padding: EdgeInsets.fromLTRB(
                                                    compact ? 16 : 24,
                                                    20,
                                                    compact ? 16 : 24,
                                                    24,
                                                  ),
                                                  child: Align(
                                                    alignment: compact
                                                        ? Alignment.center
                                                        : Alignment.centerLeft,
                                                    child: Image.asset(
                                                      'assets/icons/sakuga.png',
                                                      key: const ValueKey(
                                                        'sidebar-logo',
                                                      ),
                                                      width: 32,
                                                      height: 32,
                                                      semanticLabel: l.appTitle,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              children: [
                                                FSidebarGroup(
                                                  children: [
                                                    for (
                                                      var i = 0;
                                                      i < labels.length;
                                                      i++
                                                    )
                                                      FSidebarItem(
                                                        icon: compact
                                                            ? Expanded(
                                                                child: Center(
                                                                  child: Icon(
                                                                    icons[i],
                                                                    semanticLabel:
                                                                        labels[i],
                                                                  ),
                                                                ),
                                                              )
                                                            : Icon(icons[i]),
                                                        label: compact
                                                            ? null
                                                            : Text(labels[i]),
                                                        selected:
                                                            shell
                                                                .currentIndex ==
                                                            i,
                                                        onPress: () =>
                                                            shell.goBranch(i),
                                                      ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.only(
                                        topLeft: mobile || immersiveDesktop
                                            ? Radius.zero
                                            : theme
                                                  .style
                                                  .borderRadius
                                                  .lg
                                                  .topLeft,
                                      ),
                                      border: mobile || immersiveDesktop
                                          ? null
                                          : Border(
                                              top: BorderSide(
                                                color: dividerColor,
                                                width: theme.style.borderWidth,
                                              ),
                                              left: BorderSide(
                                                color: dividerColor,
                                                width: theme.style.borderWidth,
                                              ),
                                            ),
                                    ),
                                    child: FScaffold(
                                      scaffoldStyle: .delta(
                                        backgroundColor: const Color(
                                          0x00000000,
                                        ),
                                        sidebarBackgroundColor: const Color(
                                          0x00000000,
                                        ),
                                        footerDecoration: .boxDelta(
                                          border: Border(
                                            top: BorderSide(
                                              color: dividerColor,
                                              width: theme.style.borderWidth,
                                            ),
                                          ),
                                        ),
                                      ),
                                      childPad: false,
                                      header: backLocation != null
                                          ? FHeader.nested(
                                              title: Text(
                                                labels[shell.currentIndex],
                                              ),
                                              titleAlignment:
                                                  AlignmentDirectional
                                                      .centerStart,
                                              suffixes: [
                                                if (!window.available ||
                                                    window.fullScreen)
                                                  ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxWidth: 160,
                                                        ),
                                                    child:
                                                        const LibraryServerAction(
                                                          compact: true,
                                                        ),
                                                  ),
                                              ],
                                              prefixes: [
                                                FHeaderAction.back(
                                                  key: const ValueKey(
                                                    'appbar-back',
                                                  ),
                                                  semanticsLabel: l.back,
                                                  semanticsTooltip: l.back,
                                                  onPress: () {
                                                    if (context.canPop()) {
                                                      context.pop();
                                                    } else {
                                                      context.go(backLocation!);
                                                    }
                                                  },
                                                ),
                                              ],
                                            )
                                          : mobile && !immersiveMobile
                                          ? mobileHeader
                                          : null,
                                      footer: mobile
                                          ? FBottomNavigationBar(
                                              style: .delta(
                                                decoration: .boxDelta(
                                                  color: null,
                                                  border: Border(
                                                    top: BorderSide(
                                                      color: dividerColor,
                                                      width: theme
                                                          .style
                                                          .borderWidth,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              index: shell.currentIndex,
                                              onChange: shell.goBranch,
                                              children: [
                                                for (
                                                  var i = 0;
                                                  i < labels.length;
                                                  i++
                                                )
                                                  FBottomNavigationBarItem(
                                                    icon: Icon(icons[i]),
                                                    label: Text(labels[i]),
                                                  ),
                                              ],
                                            )
                                          : null,
                                      child: _immersiveContent(
                                        ref,
                                        immersive:
                                            immersiveDesktop || immersiveMobile,
                                        desktopInset: immersiveDesktop ? 48 : 0,
                                        header: immersiveMobile
                                            ? ImmersiveChrome(
                                                active: true,
                                                overArtworkTheme:
                                                    overArtworkTheme,
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    top: MediaQuery.paddingOf(
                                                      context,
                                                    ).top,
                                                  ),
                                                  child: mobileHeader,
                                                ),
                                              )
                                            : null,
                                        child: LibraryServerHeaderScope(
                                          hasServerAction:
                                              isLibraryRootRoute &&
                                              ((window.available &&
                                                      !window.fullScreen) ||
                                                  mobile ||
                                                  backLocation != null),
                                          child: shell,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (titleBar != null && immersiveDesktop)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 48,
                          child: ImmersiveChrome(
                            active: true,
                            overArtworkTheme: overArtworkTheme,
                            child: titleBar,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Wraps the routed pages so an immersive home can lay its artwork under the
/// window chrome, and tracks whether it has scrolled away from under it.
Widget _immersiveContent(
  WidgetRef ref, {
  required bool immersive,
  required double desktopInset,
  required Widget? header,
  required Widget child,
}) {
  final tracked = NotificationListener<ScrollUpdateNotification>(
    onNotification: (notification) {
      if (immersive &&
          notification.depth == 0 &&
          notification.metrics.axis == Axis.vertical) {
        ref
            .read(immersiveScrolledProvider.notifier)
            .set(notification.metrics.pixels > 4);
      }
      return false;
    },
    child: child,
  );
  if (header == null) {
    return ImmersiveScope(
      active: immersive,
      topInset: desktopInset,
      child: tracked,
    );
  }
  return _OverlaidHeader(header: header, child: tracked);
}

/// Lays the phone header over the page and reports its measured height as
/// the page's immersive top inset.
class _OverlaidHeader extends StatefulWidget {
  const _OverlaidHeader({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  State<_OverlaidHeader> createState() => _OverlaidHeaderState();
}

class _OverlaidHeaderState extends State<_OverlaidHeader> {
  final _headerKey = GlobalKey();
  double _height = 0;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant _OverlaidHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _headerKey.currentContext?.size?.height;
      if (height != null && height != _height) {
        setState(() => _height = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ImmersiveScope(
          active: true,
          topInset: _height,
          child: widget.child,
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _scheduleMeasure();
            return true;
          },
          child: SizeChangedLayoutNotifier(
            child: KeyedSubtree(key: _headerKey, child: widget.header),
          ),
        ),
      ),
    ],
  );
}

Future<void> _update(
  BuildContext context,
  WidgetRef ref,
  AppSettings Function(AppSettings) transform,
) async {
  try {
    await ref.read(settingsProvider.notifier).update(transform);
  } catch (error) {
    if (context.mounted) notifyUser(context, failureMessage(context, error));
  }
}

/// Fades the mobile header title between the branch labels, matching the
/// transition of the page below it instead of swapping the text abruptly.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 180),
    // The header stretches the title to the full width of an Expanded. The
    // default switcher layout centres its children, which would centre the
    // title, so keep the incoming and outgoing labels start aligned.
    layoutBuilder: (current, previous) => Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [...previous, ?current],
    ),
    child: Text(label, key: ValueKey(label)),
  );
}

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    required this.controller,
    this.compactSidebar = true,
    this.onToggleCompactSidebar,
    this.language = 'system',
    this.onLanguageChanged,
    this.onToggleTheme,
    this.libraryServerAction,
    this.homeAction,
    super.key,
  });
  final DesktopWindowController controller;

  /// Page action hosted in the title bar while the home artwork extends
  /// underneath it.
  final Widget? homeAction;
  final bool compactSidebar;
  final Future<void> Function()? onToggleCompactSidebar;
  final String language;
  final Future<void> Function(String language)? onLanguageChanged;
  final Future<void> Function()? onToggleTheme;
  final Widget? libraryServerAction;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (controller.macOS) ...[
            const SizedBox(width: 12),
            _MacWindowControls(controller: controller),
            const SizedBox(width: 12),
          ],
          if (onToggleCompactSidebar != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FButton.icon(
                key: const ValueKey('toggle-compact-sidebar'),
                variant: .ghost,
                size: .xs,
                semanticsLabel: l.compactSidebar,
                onPress: onToggleCompactSidebar,
                child: Icon(
                  compactSidebar
                      ? FLucideIcons.panelLeftOpen
                      : FLucideIcons.panelLeftClose,
                  size: 16,
                ),
              ),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => controller.drag(),
              onDoubleTap: controller.toggleMaximize,
              child: Padding(
                padding: EdgeInsets.only(
                  left: onToggleCompactSidebar != null ? 4 : 16,
                  right: 16,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l.appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.theme.typography.body.sm.copyWith(
                      color: controller.focused
                          ? context.theme.colors.foreground
                          : context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (homeAction case final action?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: action,
            ),
          if (libraryServerAction case final action?)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: action,
            ),
          if (onLanguageChanged != null)
            _LanguageMenu(
              key: const ValueKey('language-menu'),
              label: l.language,
              language: language,
              onChanged: onLanguageChanged!,
            ),
          if (onToggleTheme != null)
            _TitleAction(
              key: const ValueKey('toggle-theme'),
              label: l.theme,
              icon: context.theme.colors.brightness == Brightness.dark
                  ? FLucideIcons.sun
                  : FLucideIcons.moon,
              callback: onToggleTheme!,
            ),
          if (!controller.macOS) ...[
            _WindowButton(l.minimize, FLucideIcons.minus, controller.minimize),
            _WindowButton(
              controller.maximized ? l.restore : l.maximize,
              controller.maximized ? FLucideIcons.copy : FLucideIcons.square,
              controller.toggleMaximize,
            ),
            _WindowButton(l.close, FLucideIcons.x, controller.close),
          ],
        ],
      ),
    );
  }
}

class _TitleAction extends StatelessWidget {
  const _TitleAction({
    required this.label,
    required this.icon,
    required this.callback,
    super.key,
  });
  final String label;
  final IconData icon;
  final Future<void> Function() callback;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: FButton.icon(
      variant: .ghost,
      size: .xs,
      semanticsLabel: label,
      onPress: callback,
      child: Icon(icon, size: 16),
    ),
  );
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.label,
    required this.language,
    required this.onChanged,
    super.key,
  });
  final String label;
  final String language;
  final Future<void> Function(String language) onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (final (value, text) in languageOptions(context))
              FItem(
                key: ValueKey('language-option-$value'),
                title: Text(text),
                selected: language == value,
                suffix: language == value
                    ? const Icon(FLucideIcons.check, size: 16)
                    : null,
                onPress: () {
                  controller.hide();
                  onChanged(value);
                },
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        variant: .ghost,
        size: .xs,
        semanticsLabel: label,
        onPress: controller.toggle,
        child: const Icon(FLucideIcons.languages, size: 16),
      ),
    ),
  );
}

class _WindowButton extends StatelessWidget {
  const _WindowButton(this.label, this.icon, this.callback);
  final String label;
  final IconData icon;
  final Future<void> Function() callback;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: FButton.icon(
      variant: .ghost,
      semanticsLabel: label,
      onPress: () async {
        try {
          await callback();
        } catch (e) {
          if (context.mounted) notifyUser(context, failureMessage(context, e));
        }
      },
      child: Icon(icon, size: 16),
    ),
  );
}

class _MacWindowControls extends StatefulWidget {
  const _MacWindowControls({required this.controller});
  final DesktopWindowController controller;

  @override
  State<_MacWindowControls> createState() => _MacWindowControlsState();
}

class _MacWindowControlsState extends State<_MacWindowControls> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final controller = widget.controller;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MacWindowButton(
            key: const ValueKey('mac-close'),
            label: l.close,
            color: const Color(0xffff5f57),
            callback: controller.close,
            glyph: _MacWindowGlyph.close,
            hovered: _hovered,
          ),
          _MacWindowButton(
            key: const ValueKey('mac-minimize'),
            label: l.minimize,
            color: const Color(0xffffbd2e),
            callback: controller.minimize,
            glyph: _MacWindowGlyph.minimize,
            hovered: _hovered,
          ),
          _MacWindowButton(
            key: const ValueKey('mac-maximize'),
            label: controller.maximized ? l.restore : l.maximize,
            color: const Color(0xff28c840),
            callback: controller.toggleMaximize,
            glyph: _MacWindowGlyph.maximize,
            hovered: _hovered,
            maximized: controller.maximized,
          ),
        ],
      ),
    );
  }
}

enum _MacWindowGlyph { close, minimize, maximize }

class _MacWindowGlyphPainter extends CustomPainter {
  const _MacWindowGlyphPainter(this.glyph, this.maximized);
  final _MacWindowGlyph glyph;
  final bool maximized;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12, size.height / 12);
    final paint = Paint()
      ..color = const Color(0x99000000)
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    switch (glyph) {
      case _MacWindowGlyph.close:
        canvas.drawLine(const Offset(3.8, 3.8), const Offset(8.2, 8.2), paint);
        canvas.drawLine(const Offset(8.2, 3.8), const Offset(3.8, 8.2), paint);
      case _MacWindowGlyph.minimize:
        canvas.drawLine(const Offset(3, 6), const Offset(9, 6), paint);
      case _MacWindowGlyph.maximize:
        final path = Path();
        if (maximized) {
          path.moveTo(5, 5);
          path.lineTo(1.5, 5);
          path.lineTo(5, 1.5);
          path.close();
          path.moveTo(7, 7);
          path.lineTo(10.5, 7);
          path.lineTo(7, 10.5);
        } else {
          path.moveTo(3, 3);
          path.lineTo(7, 3);
          path.lineTo(3, 7);
          path.close();
          path.moveTo(9, 9);
          path.lineTo(5, 9);
          path.lineTo(9, 5);
        }
        path.close();
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MacWindowGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || maximized != oldDelegate.maximized;
}

class _MacWindowButton extends StatelessWidget {
  const _MacWindowButton({
    required this.label,
    required this.color,
    required this.callback,
    required this.glyph,
    required this.hovered,
    this.maximized = false,
    super.key,
  });
  final String label;
  final Color color;
  final _MacWindowGlyph glyph;
  final bool hovered;
  final bool maximized;
  final Future<void> Function() callback;
  @override
  Widget build(BuildContext context) {
    void invoke() {
      callback().catchError((error) {
        if (context.mounted) {
          notifyUser(context, failureMessage(context, error));
        }
      });
    }

    return Semantics(
      button: true,
      label: label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.basic,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              invoke();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: invoke,
          child: SizedBox(
            width: 20,
            height: 24,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: hovered
                      ? CustomPaint(
                          key: ValueKey('mac-glyph-${glyph.name}'),
                          painter: _MacWindowGlyphPainter(glyph, maximized),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
