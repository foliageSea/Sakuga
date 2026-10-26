import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/jellyfin/jellyfin_client.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../detail/detail_providers.dart';
import '../home/home_providers.dart';
import '../library/library_providers.dart';
import 'player_assets.dart';
import 'playback_progress_repository.dart';

/// Full-screen Jellyfin player.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({this.itemId, super.key});

  /// The Jellyfin item to play. Null on the dev route, which plays
  /// [DEV_MEDIA_URL] instead of a library item.
  final String? itemId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver {
  static const _devMediaUrl = String.fromEnvironment('DEV_MEDIA_URL');
  static const _localSaveInterval = Duration(seconds: 5);
  static const _serverSyncInterval = Duration(seconds: 10);
  static const _exitSyncTimeout = Duration(seconds: 7);

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
  JellyfinClient? _client;
  JellyfinPlaybackSession? _playbackSession;
  String? _serverId;
  String? _userId;
  String? _progressItemId;
  Duration _position = Duration.zero;
  Duration _initialPosition = Duration.zero;
  Duration _positionOffset = Duration.zero;
  bool _receivedPlayerPosition = false;
  bool _playing = false;
  bool _tracking = false;
  bool _stopped = false;
  bool _exiting = false;
  bool _allowPop = false;
  bool _backgroundCheckpointed = false;
  int _lastLocalSaveTicks = -1;
  Timer? _progressTimer;
  Future<void> _localTail = Future.value();
  Future<void> _syncTail = Future.value();
  int _progressRevision = 0;
  late final PlaybackProgressRepository _progressRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progressRepository = ref.read(playbackProgressRepositoryProvider);
    _player = Player();
    _controller = VideoController(_player);
    _tracks = _player.state.tracks;
    _track = _player.state.track;
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        final changed = playing != _playing;
        _playing = playing;
        if (playing && mounted) setState(() => _loading = false);
        if (changed && _tracking) unawaited(_checkpoint(report: true));
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((position) {
        _position = position;
        if (_position + _positionOffset > Duration.zero ||
            _initialPosition == Duration.zero) {
          _receivedPlayerPosition = true;
        }
        if (_tracking &&
            (_positionTicks - _lastLocalSaveTicks).abs() >=
                _durationToTicks(_localSaveInterval)) {
          _lastLocalSaveTicks = _positionTicks;
          unawaited(_checkpoint());
        }
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
    if (_tracking) {
      await _stopTracking(failed: _error != null)
          .timeout(_exitSyncTimeout, onTimeout: () {});
    }
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
      final serverTicks =
          (item.userData?['PlaybackPositionTicks'] as num?)?.toInt() ?? 0;
      final localTicks = await _loadLocalProgress(
        serverId: library.client.server.id,
        userId: library.userId,
        itemId: itemId,
      );
      final ticks = localTicks ?? serverTicks;
      final source = await library.client.playbackSource(
        library.userId,
        itemId,
        startTimeTicks: ticks,
      );
      if (!mounted || generation != _openGeneration) return;
      _client = library.client;
      _playbackSession = source.session;
      _serverId = library.client.server.id;
      _userId = library.userId;
      _progressItemId = itemId;
      _position = source.initialPosition;
      _initialPosition = source.initialPosition;
      _positionOffset = source.positionOffset;
      _receivedPlayerPosition = false;
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
      await _startTracking();
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

  Future<int?> _loadLocalProgress({
    required String serverId,
    required String userId,
    required String itemId,
  }) async {
    try {
      return await _progressRepository.load(
        serverId: serverId,
        userId: userId,
        itemId: itemId,
      );
    } catch (error, stackTrace) {
      debugPrint('PLAYER_LOCAL_PROGRESS_READ_ERROR $error\n$stackTrace');
      return null;
    }
  }

  Future<void> _startTracking() async {
    _tracking = true;
    _stopped = false;
    _lastLocalSaveTicks = _positionTicks;
    await _checkpoint(started: true);
    if (!_tracking || _stopped || !mounted) return;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      _serverSyncInterval,
      (_) => unawaited(_checkpoint(report: true)),
    );
  }

  Future<void> _checkpoint({
    bool started = false,
    bool report = false,
    bool stopped = false,
    bool failed = false,
  }) {
    final client = _client;
    final session = _playbackSession;
    final serverId = _serverId;
    final userId = _userId;
    final itemId = _progressItemId;
    if (!_tracking ||
        client == null ||
        session == null ||
        serverId == null ||
        userId == null ||
        itemId == null) {
      return Future.value();
    }

    final positionTicks = _positionTicks;
    final isPaused = !_playing;
    final volume = _player.state.volume;
    final revision = ++_progressRevision;
    final localSave = _serializeLocal(() async {
      try {
        await _progressRepository.save(
          serverId: serverId,
          userId: userId,
          itemId: itemId,
          positionTicks: positionTicks,
        );
      } catch (error, stackTrace) {
        debugPrint('PLAYER_LOCAL_PROGRESS_WRITE_ERROR $error\n$stackTrace');
      }
    });

    if (!started && !report && !stopped) return localSave;
    return _serializeSync(() async {
      await localSave;
      // On exit, discard queued periodic/pause reports and send only the
      // newest Stopped snapshot after any request already in flight.
      if (!stopped && revision != _progressRevision) return;
      try {
        try {
          if (stopped) {
            await client.reportPlaybackStopped(
              session,
              positionTicks: positionTicks,
              failed: failed,
              volume: volume,
            );
          } else if (started) {
            await client.reportPlaybackStarted(
              session,
              positionTicks: positionTicks,
              isPaused: isPaused,
              volume: volume,
            );
          } else {
            await client.reportPlaybackProgress(
              session,
              positionTicks: positionTicks,
              isPaused: isPaused,
              volume: volume,
            );
          }
        } catch (error, stackTrace) {
          debugPrint('PLAYER_SESSION_SYNC_ERROR $error\n$stackTrace');
        }
        await client.updatePlaybackPosition(
          userId,
          itemId,
          positionTicks: positionTicks,
        );
        await _clearLocalIfCurrent(
          revision: revision,
          serverId: serverId,
          userId: userId,
          itemId: itemId,
          positionTicks: positionTicks,
        );
      } catch (error, stackTrace) {
        debugPrint('PLAYER_PROGRESS_SYNC_ERROR $error\n$stackTrace');
      }
    });
  }

  Future<void> _clearLocalIfCurrent({
    required int revision,
    required String serverId,
    required String userId,
    required String itemId,
    required int positionTicks,
  }) => _serializeLocal(() async {
    if (revision != _progressRevision) return;
    await _progressRepository.clearIfMatches(
      serverId: serverId,
      userId: userId,
      itemId: itemId,
      positionTicks: positionTicks,
    );
  });

  Future<void> _serializeLocal(Future<void> Function() operation) {
    final next = _localTail.then((_) => operation());
    _localTail = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('PLAYER_LOCAL_PROGRESS_QUEUE_ERROR $error\n$stackTrace');
    });
    return next;
  }

  Future<void> _serializeSync(Future<void> Function() operation) {
    final next = _syncTail.then((_) => operation());
    _syncTail = next.catchError((Object error, StackTrace stackTrace) {
      debugPrint('PLAYER_PROGRESS_QUEUE_ERROR $error\n$stackTrace');
    });
    return next;
  }

  int get _positionTicks => _durationToTicks(
    _receivedPlayerPosition ? _position + _positionOffset : _initialPosition,
  );

  static int _durationToTicks(Duration duration) =>
      duration.inMicroseconds * 10;

  Future<void> _stopTracking({bool failed = false}) async {
    if (!_tracking || _stopped) return _syncTail;
    _stopped = true;
    _progressTimer?.cancel();
    final stopping = _checkpoint(stopped: true, failed: failed);
    _tracking = false;
    await stopping;
  }

  Future<void> _exitPlayer() async {
    if (_exiting) return;
    _exiting = true;
    await _stopTracking(failed: _error != null)
        .timeout(_exitSyncTimeout, onTimeout: () {});
    if (!mounted) return;
    ref.invalidate(resumeItemsProvider);
    final userId = _userId;
    final itemId = _progressItemId;
    if (userId != null && itemId != null) {
      ref.invalidate(libraryItemProvider((userId: userId, itemId: itemId)));
    }
    setState(() => _allowPop = true);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_tracking) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_backgroundCheckpointed) {
          _backgroundCheckpointed = true;
          unawaited(_checkpoint(report: true));
        }
      case AppLifecycleState.detached:
        unawaited(_stopTracking(failed: _error != null));
      case AppLifecycleState.resumed:
        _backgroundCheckpointed = false;
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
    WidgetsBinding.instance.removeObserver(this);
    _openGeneration++;
    _progressTimer?.cancel();
    if (_tracking && !_stopped) {
      unawaited(_stopTracking(failed: _error != null));
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exitPlayer());
      },
      child: ColoredBox(
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
                      onPress: _exitPlayer,
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
