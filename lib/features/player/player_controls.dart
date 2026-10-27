import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/settings/settings.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';
import 'player_subtitles.dart';
import 'player_controls_controller.dart';
import 'player_slider.dart';
import 'player_shortcuts.dart';

JellyfinItem? nextPlayerEpisode(List<JellyfinItem> episodes, String? itemId) {
  final index = episodes.indexWhere((episode) => episode.id == itemId);
  return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
}

class PlayerControls extends ConsumerStatefulWidget {
  const PlayerControls({
    required this.controller,
    required this.onToggleFullscreen,
    required this.onExitFullscreen,
    required this.fullscreen,
    required this.header,
    required this.itemId,
    required this.switching,
    required this.onSelectEpisode,
    this.onScreenshot,
    this.topLeftOverlay,
    super.key,
  });

  final PlayerControlsController controller;
  final Future<void> Function() onToggleFullscreen;
  final Future<void> Function() onExitFullscreen;
  final bool fullscreen;
  final Widget header;
  final ValueListenable<String?> itemId;
  final ValueListenable<bool> switching;
  final Future<void> Function(JellyfinItem) onSelectEpisode;
  final Future<void> Function()? onScreenshot;
  final Widget? topLeftOverlay;

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<PlayerControls> {
  Timer? _hideTimer;
  bool _visible = true;
  bool _hoveringBar = false;
  bool _overlayFocused = false;
  Duration? _scrubPosition;
  double _unmutedVolume = 100;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPlaybackChanged);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onPlaybackChanged);
      widget.controller.addListener(_onPlaybackChanged);
    }
  }

  void _onPlaybackChanged() {
    if (!widget.controller.playing) {
      _hideTimer?.cancel();
      if (!_visible && mounted) setState(() => _visible = true);
    } else if (_hideTimer == null) {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!widget.controller.playing ||
        _hoveringBar ||
        _overlayFocused ||
        _scrubPosition != null) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      _hideTimer = null;
      if (mounted) setState(() => _visible = false);
    });
  }

  void _reveal() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _hoverBar(bool hovering) {
    _hoveringBar = hovering;
    if (hovering) {
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    _reveal();
    try {
      await action();
    } catch (error) {
      if (mounted) notifyUser(context, failureMessage(context, error));
    }
  }

  Future<void> _seekBy(int seconds) {
    final controller = widget.controller;
    final milliseconds = (controller.position.inMilliseconds + seconds * 1000)
        .clamp(0, controller.duration.inMilliseconds);
    return _perform(
      () => controller.seek(Duration(milliseconds: milliseconds)),
    );
  }

  Future<void> _changeVolume(double value) =>
      _perform(() => widget.controller.setVolume(value.clamp(0, 100)));

  @override
  void dispose() {
    widget.controller.removeListener(_onPlaybackChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    Widget episodeButton({bool menu = false}) => PlayerEpisodeButton(
      itemId: widget.itemId,
      switching: widget.switching,
      onSelectEpisode: widget.onSelectEpisode,
      menu: menu,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _perform(widget.controller.playOrPause),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _seekBy(-settings.seekBackwardSeconds),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _seekBy(settings.seekForwardSeconds),
        if (widget.onScreenshot case final screenshot?)
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            includeRepeats: false,
          ): () =>
              unawaited(screenshot()),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _changeVolume(widget.controller.volume + 5),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _changeVolume(widget.controller.volume - 5),
        const SingleActivator(LogicalKeyboardKey.keyF): () =>
            _perform(widget.onToggleFullscreen),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (widget.fullscreen) _perform(widget.onExitFullscreen);
        },
      },
      child: Focus(
        autofocus: true,
        onFocusChange: (focused) {
          _overlayFocused = !focused;
          _scheduleHide();
        },
        child: MouseRegion(
          cursor: _visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _reveal(),
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _changeVolume(
                  widget.controller.volume - event.scrollDelta.dy / 10,
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const ValueKey('player-control-surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_visible) {
                      setState(() => _visible = false);
                      _hideTimer?.cancel();
                    } else {
                      _reveal();
                    }
                  },
                  onDoubleTap: () => _perform(widget.onToggleFullscreen),
                ),
                IgnorePointer(
                  ignoring: !_visible,
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: MouseRegion(
                            onEnter: (_) => _hoverBar(true),
                            onExit: (_) => _hoverBar(false),
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x99000000),
                                    Color(0x00000000),
                                  ],
                                ),
                              ),
                              child: SafeArea(
                                bottom: false,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: widget.header,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: MouseRegion(
                            onEnter: (_) => _hoverBar(true),
                            onExit: (_) => _hoverBar(false),
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x00000000),
                                    Color(0xCC000000),
                                  ],
                                ),
                              ),
                              child: SafeArea(
                                top: false,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    20,
                                    16,
                                    12,
                                  ),
                                  child: ListenableBuilder(
                                    listenable: widget.controller,
                                    builder: (context, _) => LayoutBuilder(
                                      builder: (context, constraints) {
                                        final controller = widget.controller;
                                        final duration =
                                            controller.duration.inMilliseconds;
                                        final position =
                                            _scrubPosition ??
                                            controller.position;
                                        final narrow =
                                            constraints.maxWidth < 560;
                                        final time =
                                            '${formatPlayerTime(position)} / ${formatPlayerTime(controller.duration)}';
                                        return Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Semantics(
                                              label: l.playbackPosition,
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  if (duration > 0)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                          ),
                                                      child: FractionallySizedBox(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        widthFactor:
                                                            (controller
                                                                        .buffer
                                                                        .inMilliseconds /
                                                                    duration)
                                                                .clamp(0, 1),
                                                        child: Container(
                                                          height: 4,
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0x55FFFFFF,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  PlayerSlider(
                                                    key: const ValueKey(
                                                      'player-seek',
                                                    ),
                                                    enabled: duration > 0,
                                                    value: duration > 0
                                                        ? position.inMilliseconds /
                                                              duration
                                                        : 0,
                                                    tooltipBuilder: (value) =>
                                                        Text(
                                                          formatPlayerTime(
                                                            Duration(
                                                              milliseconds:
                                                                  (duration *
                                                                          value)
                                                                      .round(),
                                                            ),
                                                          ),
                                                        ),
                                                    onChange: (value) {
                                                      _hideTimer?.cancel();
                                                      setState(
                                                        () => _scrubPosition =
                                                            Duration(
                                                              milliseconds:
                                                                  (duration *
                                                                          value)
                                                                      .round(),
                                                            ),
                                                      );
                                                    },
                                                    onEnd: (value) async {
                                                      await _perform(
                                                        () => controller.seek(
                                                          Duration(
                                                            milliseconds:
                                                                (duration *
                                                                        value)
                                                                    .round(),
                                                          ),
                                                        ),
                                                      );
                                                      if (mounted) {
                                                        setState(
                                                          () => _scrubPosition =
                                                              null,
                                                        );
                                                        _scheduleHide();
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (narrow)
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  time,
                                                  style: context
                                                      .theme
                                                      .typography
                                                      .body
                                                      .xs
                                                      .copyWith(
                                                        color: const Color(
                                                          0xFFFFFFFF,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            Row(
                                              children: [
                                                PlayerControlButton(
                                                  key: const ValueKey(
                                                    'player-play-pause',
                                                  ),
                                                  label: controller.playing
                                                      ? l.pausePlayback
                                                      : l.playPlayback,
                                                  icon: controller.playing
                                                      ? FLucideIcons.pause
                                                      : FLucideIcons.play,
                                                  onPress: () => _perform(
                                                    controller.playOrPause,
                                                  ),
                                                ),
                                                episodeButton(),
                                                PlayerControlButton(
                                                  key: const ValueKey(
                                                    'player-mute',
                                                  ),
                                                  label: controller.volume == 0
                                                      ? l.unmute
                                                      : l.mute,
                                                  icon: controller.volume == 0
                                                      ? FLucideIcons.volumeX
                                                      : FLucideIcons.volume2,
                                                  onPress: () {
                                                    if (controller.volume > 0) {
                                                      _unmutedVolume =
                                                          controller.volume;
                                                    }
                                                    _changeVolume(
                                                      controller.volume == 0
                                                          ? _unmutedVolume
                                                          : 0,
                                                    );
                                                  },
                                                ),
                                                if (!narrow) ...[
                                                  SizedBox(
                                                    width: 80,
                                                    child: PlayerSlider(
                                                      key: const ValueKey(
                                                        'player-volume',
                                                      ),
                                                      value:
                                                          controller.volume /
                                                          100,
                                                      onChange: (value) =>
                                                          _changeVolume(
                                                            value * 100,
                                                          ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Text(
                                                    time,
                                                    style: context
                                                        .theme
                                                        .typography
                                                        .body
                                                        .sm
                                                        .copyWith(
                                                          color: const Color(
                                                            0xFFFFFFFF,
                                                          ),
                                                        ),
                                                  ),
                                                ],
                                                const Spacer(),
                                                episodeButton(menu: true),
                                                PlayerControlButton(
                                                  key: const ValueKey(
                                                    'player-subtitle-style',
                                                  ),
                                                  label: l.subtitleStyle,
                                                  icon: FLucideIcons
                                                      .slidersHorizontal,
                                                  onPress: () =>
                                                      showSubtitleStyleDialog(
                                                        context,
                                                      ),
                                                ),
                                                PlayerControlButton(
                                                  key: const ValueKey(
                                                    'player-shortcuts',
                                                  ),
                                                  label: l.playbackShortcuts,
                                                  icon: FLucideIcons.keyboard,
                                                  onPress: () =>
                                                      showPlayerShortcutDialog(
                                                        context,
                                                      ),
                                                ),
                                                if (widget.onScreenshot
                                                    case final screenshot?)
                                                  PlayerControlButton(
                                                    key: const ValueKey(
                                                      'player-screenshot',
                                                    ),
                                                    label: l.copyScreenshot,
                                                    icon: FLucideIcons.camera,
                                                    onPress: () =>
                                                        unawaited(screenshot()),
                                                  ),
                                                PlayerControlButton(
                                                  key: const ValueKey(
                                                    'player-fullscreen',
                                                  ),
                                                  label: widget.fullscreen
                                                      ? l.exitFullscreen
                                                      : l.enterFullscreen,
                                                  icon: widget.fullscreen
                                                      ? FLucideIcons.minimize
                                                      : FLucideIcons.maximize,
                                                  onPress: () => _perform(
                                                    widget.onToggleFullscreen,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => widget.controller.buffering
                      ? IgnorePointer(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const FCircularProgress(),
                                if (widget.controller.downloadBytesPerSecond
                                    case final speed?) ...[
                                  const SizedBox(height: 12),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0x99000000),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        formatPlayerDownloadSpeed(speed),
                                        key: const ValueKey(
                                          'player-download-speed',
                                        ),
                                        style: context.theme.typography.body.sm
                                            .copyWith(
                                              color: const Color(0xFFFFFFFF),
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (widget.topLeftOverlay case final overlay?)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: IgnorePointer(
                      child: SafeArea(
                        right: false,
                        bottom: false,
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.only(
                            left: 12,
                            top: _visible ? 56 : 12,
                          ),
                          child: overlay,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatPlayerDownloadSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1024 * 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
  }
  if (bytesPerSecond >= 1024 * 1024) {
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

String formatPlayerTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 1 << 31);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$remainder'
      : '${seconds ~/ 60}:$remainder';
}

class PlayerControlButton extends StatelessWidget {
  const PlayerControlButton({
    required this.label,
    required this.icon,
    this.onPress,
    this.iconSize = 18,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPress;
  final double iconSize;

  @override
  Widget build(BuildContext context) => FButton.icon(
    variant: .ghost,
    size: .sm,
    style: .delta(
      decoration: .delta([
        .base(
          .shapeDelta(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(2.0)),
            ),
          ),
        ),
      ]),
    ),
    semanticsLabel: label,
    onPress: onPress,
    child: Icon(
      icon,
      size: iconSize,
      color: onPress == null
          ? const Color(0x61FFFFFF)
          : const Color(0xFFFFFFFF),
    ),
  );
}

class PlayerEpisodeButton extends StatelessWidget {
  const PlayerEpisodeButton({
    required this.itemId,
    required this.switching,
    required this.onSelectEpisode,
    this.menu = false,
    this.iconSize = 18,
    super.key,
  });

  final ValueListenable<String?> itemId;
  final ValueListenable<bool> switching;
  final Future<void> Function(JellyfinItem) onSelectEpisode;
  final bool menu;
  final double iconSize;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: itemId,
    builder: (context, currentId, _) => ValueListenableBuilder(
      valueListenable: switching,
      builder: (context, busy, _) => Consumer(
        builder: (context, ref, _) {
          final userId = ref.watch(libraryViewsProvider).value?.userId;
          final item = userId == null || currentId == null
              ? null
              : ref
                    .watch(
                      libraryItemProvider((userId: userId, itemId: currentId)),
                    )
                    .value;
          final seriesId = item?.seriesId;
          if (userId == null || seriesId == null || seriesId.isEmpty) {
            return const SizedBox.shrink();
          }
          final query = (
            userId: userId,
            seriesId: seriesId,
            seasonId: null as String?,
          );
          final episodes = ref.watch(seriesEpisodesProvider(query));
          if (menu) {
            return _EpisodeMenu(
              episodes: episodes,
              currentId: currentId,
              busy: busy,
              onSelect: onSelectEpisode,
              onRetry: () => ref.invalidate(seriesEpisodesProvider(query)),
            );
          }
          final next = nextPlayerEpisode(episodes.value ?? const [], currentId);
          return PlayerControlButton(
            key: const ValueKey('player-next-episode'),
            label: context.l10n.nextEpisode,
            onPress: busy || next == null
                ? null
                : () => unawaited(onSelectEpisode(next)),
            iconSize: iconSize,
            icon: FLucideIcons.skipForward,
          );
        },
      ),
    ),
  );
}

class _EpisodeMenu extends StatelessWidget {
  const _EpisodeMenu({
    required this.episodes,
    required this.currentId,
    required this.busy,
    required this.onSelect,
    required this.onRetry,
  });

  final AsyncValue<List<JellyfinItem>> episodes;
  final String? currentId;
  final bool busy;
  final Future<void> Function(JellyfinItem) onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    maxHeight: 360,
    menuAnchor: .bottomRight,
    childAnchor: .topRight,
    menuBuilder: (context, controller, _) => [
      FItemGroup(
        children: episodes.when(
          loading: () => [FItem(title: Text(context.l10n.loading))],
          error: (_, _) => [
            FItem(title: Text(context.l10n.retry), onPress: onRetry),
          ],
          data: (values) => values.isEmpty
              ? [FItem(title: Text(context.l10n.noItems))]
              : [
                  for (final episode in values)
                    FItem(
                      key: ValueKey('player-episode-${episode.id}'),
                      title: SizedBox(
                        width: 260,
                        child: Text(
                          episode.displaySubtitle ?? episode.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      selected: episode.id == currentId,
                      suffix: episode.id == currentId
                          ? const Icon(FLucideIcons.check, size: 16)
                          : null,
                      onPress: busy
                          ? null
                          : () {
                              controller.hide();
                              unawaited(onSelect(episode));
                            },
                    ),
                ],
        ),
      ),
    ],
    builder: (context, controller, _) => PlayerControlButton(
      key: const ValueKey('player-episodes-menu'),
      label: context.l10n.selectEpisode,
      onPress: busy ? null : controller.toggle,
      icon: FLucideIcons.listVideo,
    ),
  );
}
