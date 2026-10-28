import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:forui/forui.dart';

import '../core/settings/settings.dart';
import '../core/window/desktop_window.dart';
import '../features/detail/detail_page.dart';
import '../features/home/home_providers.dart';
import '../features/library/library_providers.dart';
import '../shared/language_options.dart';
import '../shared/localization.dart';
import '../shared/poster_background.dart';
import '../shared/widgets.dart';

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
    final activeServer = isLibraryRootRoute
        ? ref.watch(activeServerProvider)
        : null;
    final canRefreshLibrary =
        isLibraryRootRoute &&
        activeServer != null &&
        activeServer.apiKey.isNotEmpty;
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
        return ListenableBuilder(
          listenable: window,
          builder: (context, _) => WindowPosterBackgroundScope(
            active: posterBackground != null,
            shellHosted: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PosterWindowBackground(background: posterBackground),
                SafeArea(
                  top: !window.available,
                  child: Column(
                    children: [
                      if (window.available && !window.fullScreen)
                        DesktopTitleBar(
                          controller: window,
                          borderColor: dividerColor,
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
                                notifyUser(
                                  context,
                                  failureMessage(context, error),
                                );
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
                                  context.theme.colors.brightness ==
                                      Brightness.dark
                                  ? ThemeMode.light
                                  : ThemeMode.dark,
                            ),
                          ),
                        ),
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
                                    : FSidebar(
                                        style: .delta(
                                          decoration: .boxDelta(
                                            color: null,
                                            border: BorderDirectional(
                                              end: BorderSide(
                                                color: dividerColor,
                                                width: theme.style.borderWidth,
                                              ),
                                            ),
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
                                                  [.disabled]: const Color(
                                                    0x00000000,
                                                  ),
                                                },
                                              ),
                                            ),
                                          ),
                                          constraints: BoxConstraints.tightFor(
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
                                                  icon: Icon(
                                                    icons[i],
                                                    semanticLabel: compact
                                                        ? labels[i]
                                                        : null,
                                                  ),
                                                  label: compact
                                                      ? null
                                                      : Text(labels[i]),
                                                  selected:
                                                      shell.currentIndex == i,
                                                  onPress: () =>
                                                      shell.goBranch(i),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            Expanded(
                              child: FScaffold(
                                scaffoldStyle: .delta(
                                  backgroundColor: const Color(0x00000000),
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
                                        title: Text(labels[shell.currentIndex]),
                                        titleAlignment:
                                            AlignmentDirectional.centerStart,
                                        prefixes: [
                                          FHeaderAction.back(
                                            key: const ValueKey('appbar-back'),
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
                                    : mobile
                                    ? Builder(
                                        builder: (headerContext) {
                                          final pad = pagePadding(
                                            headerContext,
                                          );
                                          return FHeader(
                                            key: const ValueKey(
                                              'mobile-header',
                                            ),
                                            style: .delta(
                                              padding: .value(
                                                EdgeInsets.fromLTRB(
                                                  pad,
                                                  8,
                                                  pad,
                                                  10,
                                                ),
                                              ),
                                            ),
                                            title: Row(
                                              children: [
                                                if (detailBackgroundSpec !=
                                                    null) ...[
                                                  FButton.icon(
                                                    key: const ValueKey(
                                                      'detail-back',
                                                    ),
                                                    variant: .outline,
                                                    size: .sm,
                                                    style:
                                                        detailOutlineButtonStyle(
                                                          headerContext,
                                                        ),
                                                    semanticsLabel: l.back,
                                                    onPress: () =>
                                                        popDetailRoute(
                                                          headerContext,
                                                        ),
                                                    child: const Icon(
                                                      FLucideIcons.arrowLeft,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                ],
                                                Expanded(
                                                  child: _HeaderTitle(
                                                    labels[shell.currentIndex],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            suffixes: [
                                              if (canRefreshLibrary)
                                                FButton.icon(
                                                  key: const ValueKey(
                                                    'library-refresh',
                                                  ),
                                                  variant: .outline,
                                                  size: .sm,
                                                  semanticsLabel: l.refresh,
                                                  onPress: () => ref.invalidate(
                                                    libraryViewsProvider,
                                                  ),
                                                  child: const Icon(
                                                    FLucideIcons.refreshCw,
                                                  ),
                                                ),
                                            ],
                                          );
                                        },
                                      )
                                    : null,
                                footer: mobile
                                    ? FBottomNavigationBar(
                                        style: .delta(
                                          decoration: .boxDelta(
                                            color: null,
                                            border: Border(
                                              top: BorderSide(
                                                color: dividerColor,
                                                width: theme.style.borderWidth,
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
                                child: shell,
                              ),
                            ),
                          ],
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
    this.borderColor,
    this.compactSidebar = true,
    this.onToggleCompactSidebar,
    this.language = 'system',
    this.onLanguageChanged,
    this.onToggleTheme,
    super.key,
  });
  final DesktopWindowController controller;
  final Color? borderColor;
  final bool compactSidebar;
  final Future<void> Function()? onToggleCompactSidebar;
  final String language;
  final Future<void> Function(String language)? onLanguageChanged;
  final Future<void> Function()? onToggleTheme;
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor ?? context.theme.colors.border),
        ),
      ),
      child: Row(
        children: [
          if (controller.macOS) ...[
            const SizedBox(width: 12),
            _MacWindowButton(
              key: const ValueKey('mac-close'),
              label: l.close,
              color: const Color(0xffff5f57),
              callback: controller.close,
            ),
            _MacWindowButton(
              key: const ValueKey('mac-minimize'),
              label: l.minimize,
              color: const Color(0xffffbd2e),
              callback: controller.minimize,
            ),
            _MacWindowButton(
              key: const ValueKey('mac-maximize'),
              label: controller.maximized ? l.restore : l.maximize,
              color: const Color(0xff28c840),
              callback: controller.toggleMaximize,
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _MacWindowButton extends StatelessWidget {
  const _MacWindowButton({
    required this.label,
    required this.color,
    required this.callback,
    super.key,
  });
  final String label;
  final Color color;
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
                child: const SizedBox(width: 12, height: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
