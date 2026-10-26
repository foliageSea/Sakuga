import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/jellyfin/jellyfin_models.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';
import 'player_assets.dart';

/// Full-screen Jellyfin player.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({this.itemId, super.key});

  /// The Jellyfin item to play. Null on the dev route, which plays
  /// [DEV_MEDIA_URL] instead of a library item.
  final String? itemId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const _devMediaUrl = String.fromEnvironment('DEV_MEDIA_URL');

  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _loading = true;
  Object? _error;
  int _openGeneration = 0;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  SuperResolutionMode _superResolutionMode = SuperResolutionMode.off;
  PlayerAssets? _assets;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _tracks = _player.state.tracks;
    _track = _player.state.track;
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (playing && mounted) setState(() => _loading = false);
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((error) {
        debugPrint('PLAYER_ERROR $error');
        if (mounted) {
          setState(() {
            _loading = false;
            _error = error;
          });
        }
      }),
    );
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        if (mounted) setState(() => _tracks = tracks);
      }),
    );
    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (mounted) setState(() => _track = track);
      }),
    );
    unawaited(_openMedia());
  }

  Future<void> _openMedia() async {
    final generation = ++_openGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final assets = await PlayerAssets.prepare();
      if (!mounted || generation != _openGeneration) return;
      _assets = assets;
      final platform = _nativePlayer;
      await platform.setProperty('sub-fonts-dir', assets.fontsDirectory.path);
      await platform.setProperty('sub-font', 'MiSans');
      await _applySuperResolution(_superResolutionMode);

      if (_devMediaUrl.isNotEmpty) {
        await _player.open(Media(_devMediaUrl), play: true);
        return;
      }

      final itemId = widget.itemId;
      if (itemId == null || itemId.isEmpty) {
        throw const FormatException('Missing media item');
      }
      final library = await ref.read(libraryViewsProvider.future);
      final item = await library.client.item(library.userId, itemId);
      final ticks =
          (item.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
      final source = await library.client.playbackSource(
        library.userId,
        itemId,
        startTimeTicks: ticks,
      );
      if (!mounted || generation != _openGeneration) return;
      await _player.open(
        Media(source.url, httpHeaders: source.headers),
        play: true,
      );
      if (source.startPosition > Duration.zero) {
        await _player.seek(source.startPosition);
      }
      if (!mounted || generation != _openGeneration) return;
      final externalSubtitleLabel = context.l10n.externalSubtitle;
      for (final subtitle in source.subtitles) {
        await platform.command([
          'sub-add',
          subtitle.url,
          'auto',
          subtitle.title ?? externalSubtitleLabel,
          subtitle.language ?? 'und',
        ]);
      }
    } catch (error, stackTrace) {
      debugPrint('PLAYER_OPEN_ERROR $error\n$stackTrace');
      if (mounted && generation == _openGeneration) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  NativePlayer get _nativePlayer {
    final platform = _player.platform;
    if (platform is NativePlayer) return platform;
    throw UnsupportedError('Native playback controls are unavailable');
  }

  Future<void> _setSuperResolution(SuperResolutionMode mode) async {
    try {
      await _applySuperResolution(mode);
      if (mounted) setState(() => _superResolutionMode = mode);
    } catch (error, stackTrace) {
      debugPrint('PLAYER_SHADER_ERROR $error\n$stackTrace');
      if (mounted) notifyUser(context, context.l10n.superResolutionError);
    }
  }

  Future<void> _applySuperResolution(SuperResolutionMode mode) async {
    final assets = _assets;
    if (assets == null) return;
    await _nativePlayer.command([
      'change-list',
      'glsl-shaders',
      mode == SuperResolutionMode.off ? 'clr' : 'set',
      mode == SuperResolutionMode.off ? '' : assets.shaderListValue(mode),
    ]);
  }

  Future<void> _setSubtitle(SubtitleTrack track) async {
    try {
      await _player.setSubtitleTrack(track);
    } catch (error, stackTrace) {
      debugPrint('PLAYER_SUBTITLE_ERROR $error\n$stackTrace');
      if (mounted) notifyUser(context, context.l10n.subtitleError);
    }
  }

  @override
  void dispose() {
    _openGeneration++;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return ColoredBox(
      color: const Color(0xff000000),
      child: Stack(
        children: [
          Positioned.fill(child: Video(controller: _controller)),
          if (_loading)
            const Positioned.fill(child: Center(child: FCircularProgress())),
          if (_error != null)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          FLucideIcons.circleAlert,
                          color: Color(0xFFFFFFFF),
                          size: 32,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.l10n.playbackError,
                          textAlign: TextAlign.center,
                          style: context.theme.typography.body.md.copyWith(
                            color: const Color(0xFFFFFFFF),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FButton(
                          builder: responsiveButtonContent,
                          variant: .outline,
                          onPress: _openMedia,
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            child: SafeArea(
              child: Row(
                children: [
                  FButton.icon(
                    key: const ValueKey('player-back'),
                    variant: .ghost,
                    onPress: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                    semanticsLabel: context.l10n.back,
                    child: const Icon(
                      FLucideIcons.arrowLeft,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  if (item != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _title(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.md.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 8),
                  _SuperResolutionMenu(
                    mode: _superResolutionMode,
                    onChanged: _setSuperResolution,
                  ),
                  const SizedBox(width: 8),
                  _SubtitleMenu(
                    tracks: _tracks.subtitle,
                    selected: _track.subtitle,
                    onChanged: _setSubtitle,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The item the route asked for, once the library session is available.
  JellyfinItem? get _item {
    final itemId = widget.itemId;
    if (itemId == null || itemId.isEmpty) return null;
    final userId = ref.watch(libraryViewsProvider).value?.userId;
    if (userId == null) return null;
    return ref
        .watch(libraryItemProvider((userId: userId, itemId: itemId)))
        .value;
  }

  String _title(JellyfinItem item) {
    final code = item.episodeCode;
    return code == null ? item.name : '$code · ${item.name}';
  }
}

class _SuperResolutionMenu extends StatelessWidget {
  const _SuperResolutionMenu({required this.mode, required this.onChanged});

  final SuperResolutionMode mode;
  final Future<void> Function(SuperResolutionMode mode) onChanged;

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuAnchor: .topRight,
    childAnchor: .bottomRight,
    menuBuilder: (context, controller, _) => [
      FItemGroup(
        children: [
          for (final value in SuperResolutionMode.values)
            FItem(
              key: ValueKey('super-resolution-${value.name}'),
              title: Text(_label(context, value)),
              selected: mode == value,
              suffix: mode == value
                  ? const Icon(FLucideIcons.check, size: 16)
                  : null,
              onPress: () {
                controller.hide();
                unawaited(onChanged(value));
              },
            ),
        ],
      ),
    ],
    builder: (context, controller, _) => FButton.icon(
      key: const ValueKey('super-resolution-menu'),
      variant: .ghost,
      onPress: controller.toggle,
      semanticsLabel: context.l10n.superResolution,
      child: Icon(
        FLucideIcons.sparkles,
        color: mode == SuperResolutionMode.off
            ? const Color(0xFFFFFFFF)
            : context.theme.colors.primary,
      ),
    ),
  );

  String _label(BuildContext context, SuperResolutionMode mode) =>
      switch (mode) {
        SuperResolutionMode.off => context.l10n.superResolutionOff,
        SuperResolutionMode.efficiency =>
          context.l10n.superResolutionEfficiency,
        SuperResolutionMode.quality => context.l10n.superResolutionQuality,
      };
}

class _SubtitleMenu extends StatelessWidget {
  const _SubtitleMenu({
    required this.tracks,
    required this.selected,
    required this.onChanged,
  });

  final List<SubtitleTrack> tracks;
  final SubtitleTrack selected;
  final Future<void> Function(SubtitleTrack track) onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = <SubtitleTrack>[
      SubtitleTrack.no(),
      SubtitleTrack.auto(),
      ...tracks.where((track) => track.id != 'no' && track.id != 'auto'),
    ];
    return FPopoverMenu(
      maxHeight: 420,
      menuAnchor: .topRight,
      childAnchor: .bottomRight,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (var index = 0; index < choices.length; index++)
              FItem(
                key: ValueKey('subtitle-${choices[index].id}'),
                title: Text(_label(context, choices[index], index)),
                subtitle: _details(choices[index]),
                selected: selected == choices[index],
                suffix: selected == choices[index]
                    ? const Icon(FLucideIcons.check, size: 16)
                    : null,
                onPress: () {
                  controller.hide();
                  unawaited(onChanged(choices[index]));
                },
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        key: const ValueKey('subtitle-menu'),
        variant: .ghost,
        onPress: controller.toggle,
        semanticsLabel: context.l10n.subtitles,
        child: Icon(
          selected.id == 'no'
              ? FLucideIcons.captionsOff
              : FLucideIcons.captions,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }

  String _label(BuildContext context, SubtitleTrack track, int index) {
    if (track.id == 'no') return context.l10n.subtitlesOff;
    if (track.id == 'auto') return context.l10n.subtitlesAutomatic;
    final title = track.title?.trim();
    return title == null || title.isEmpty
        ? '${context.l10n.subtitleTrack} ${index - 1}'
        : title;
  }

  Widget? _details(SubtitleTrack track) {
    final parts = [
      track.language,
      track.codec,
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }
}
