import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/media_server/media_server_client.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/playback_models.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../detail/detail_providers.dart';
import '../home/home_providers.dart';
import '../library/library_providers.dart';
import 'player_assets.dart';
import 'player_audio.dart';
import 'player_button_style.dart';
import 'player_gpu_usage.dart';
import 'playback_progress_repository.dart';
import 'player_controls.dart';
import 'player_controls_controller.dart';
import 'player_exit.dart';
import 'player_errors.dart';
import 'player_subtitles.dart';
import 'player_track_format.dart';
import 'player_screenshot.dart';

// This provider outlives the route so pending saves can refresh the library
// after the player is disposed, while still respecting container disposal.
final _refreshPlaybackProvider = Provider((ref) {
  return (String? userId, String? itemId, String? seriesId) {
    if (!ref.mounted) return;
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(libraryItemsProvider);
    ref.invalidate(seriesEpisodesProvider);
    ref.invalidate(seriesSeasonsProvider);
    if (userId != null && itemId != null) {
      ref.invalidate(libraryItemProvider((userId: userId, itemId: itemId)));
    }
    if (userId != null && seriesId != null && seriesId.isNotEmpty) {
      ref.invalidate(libraryItemProvider((userId: userId, itemId: seriesId)));
    }
  };
});

/// Full-screen media player.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({this.itemId, super.key});

  /// The media item to play. Null on the dev route, which plays
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
  late final MediaKitControlsController _controlsController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _loading = true;
  Object? _error;
  int _openGeneration = 0;
  Tracks _tracks = const Tracks();
  Track _track = const Track();
  SuperResolutionMode _superResolutionMode = SuperResolutionMode.off;
  PlayerAssets? _assets;
  MediaServerClient? _client;
  PlaybackSession? _playbackSession;
  String? _serverId;
  String? _userId;
  String? _progressItemId;
  String? _seriesId;
  int? _runtimeTicks;
  Duration _position = Duration.zero;
  Duration _initialPosition = Duration.zero;
  Duration _positionOffset = Duration.zero;
  Duration? _pendingStartPosition;
  bool _fallbackStartSeekIssued = false;
  DateTime? _fileLoadedAt;
  List<SubtitleSource> _pendingSubtitles = const [];
  String _externalSubtitleLabel = '';
  bool _subtitlesAttached = false;
  bool _receivedPlayerPosition = false;
  bool _completed = false;
  bool _playing = false;
  bool _tracking = false;
  bool _stopped = false;
  bool _exiting = false;
  bool _backgroundCheckpointed = false;
  int _lastLocalSaveTicks = -1;
  int _lastReportedTicks = -1;
  Timer? _progressTimer;
  Future<void> _localTail = Future.value();
  Future<void> _syncTail = Future.value();
  int _progressRevision = 0;
  late final PlaybackProgressRepository _progressRepository;
  late final ValueNotifier<String?> _currentItemId;
  final _switchingEpisode = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentItemId = ValueNotifier(widget.itemId);
    _progressRepository = ref.read(playbackProgressRepositoryProvider);
    _player = Player();
    _controller = VideoController(_player);
    _controlsController = MediaKitControlsController(_player);
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
        final pending = _pendingStartPosition;
        if (pending != null) {
          final threshold = _resumeThreshold(pending);
          final loadedAt = _fileLoadedAt;
          final settleExpired =
              loadedAt != null &&
              DateTime.now().difference(loadedAt) >= const Duration(seconds: 3);
          if (position >= threshold || settleExpired) {
            _pendingStartPosition = null;
            _position = position;
            _receivedPlayerPosition = true;
          }
        } else {
          _position = position;
          if (position > Duration.zero && _completed) {
            _completed = false;
          }
          if (_position + _positionOffset > Duration.zero ||
              _initialPosition == Duration.zero) {
            _receivedPlayerPosition = true;
          }
        }
        if (_tracking) {
          final currentTicks = _positionTicks;
          if ((currentTicks - _lastReportedTicks).abs() >=
              _durationToTicks(const Duration(seconds: 15))) {
            _lastLocalSaveTicks = currentTicks;
            unawaited(_checkpoint(report: true));
          } else if ((currentTicks - _lastLocalSaveTicks).abs() >=
              _durationToTicks(_localSaveInterval)) {
            _lastLocalSaveTicks = currentTicks;
            unawaited(_checkpoint());
          }
        }
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (duration <= Duration.zero) return;
        _fileLoadedAt ??= DateTime.now();
        unawaited(_onMediaLoaded(duration, _openGeneration));
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!completed) return;
        _completed = true;
        if (_tracking) unawaited(_checkpoint(report: true));
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((error) {
        debugPrint('PLAYER_ERROR $error');
        if (isExternalSubtitleLoadError(
          error,
          _pendingSubtitles.map((subtitle) => subtitle.url),
        )) {
          return;
        }
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
        if (mounted) {
          setState(() => _tracks = tracks);
          _syncSubtitleRendering();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (mounted) {
          setState(() => _track = track);
          _syncSubtitleRendering();
        }
      }),
    );
    unawaited(_openMedia());
  }

  static Duration _resumeThreshold(Duration target) =>
      target > const Duration(seconds: 2)
      ? target - const Duration(seconds: 2)
      : Duration(microseconds: target.inMicroseconds ~/ 2);

  Future<void> _onMediaLoaded(Duration duration, int generation) async {
    if (!mounted || generation != _openGeneration) return;
    if (!_subtitlesAttached && _pendingSubtitles.isNotEmpty) {
      _subtitlesAttached = true;
      for (final subtitle in _pendingSubtitles) {
        if (!mounted || generation != _openGeneration) return;
        try {
          await _nativePlayer.command([
            'sub-add',
            subtitle.url,
            'auto',
            subtitle.title ?? _externalSubtitleLabel,
            subtitle.language ?? 'und',
          ]);
        } catch (error, stackTrace) {
          debugPrint('PLAYER_SUBTITLE_ADD_ERROR $error\n$stackTrace');
        }
      }
    }
    final pending = _pendingStartPosition;
    if (pending == null) return;
    if (pending >= duration) {
      _pendingStartPosition = null;
      return;
    }
    if (!_fallbackStartSeekIssued &&
        _player.state.position < _resumeThreshold(pending)) {
      _fallbackStartSeekIssued = true;
      await _player.seek(pending);
    }
  }

  Future<void> _openMedia() async {
    if (_exiting || !mounted) return;
    if (_tracking) {
      await _stopTracking(failed: _error != null)
          .timeout(_exitSyncTimeout, onTimeout: () {});
    }
    if (_exiting || !mounted) return;
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
      if (!mounted || generation != _openGeneration) return;

      if (_devMediaUrl.isNotEmpty) {
        await _player.open(Media(_devMediaUrl), play: true);
        return;
      }

      final itemId = _currentItemId.value;
      if (itemId == null || itemId.isEmpty) {
        throw const FormatException('Missing media item');
      }
      final library = await ref.read(libraryViewsProvider.future);
      if (!mounted || generation != _openGeneration) return;
      final item = await library.client.item(library.userId, itemId);
      if (!mounted || generation != _openGeneration) return;
      final serverTicks = _durationToTicks(
        item.playbackPosition ?? Duration.zero,
      );
      final localTicks = await _loadLocalProgress(
        serverId: library.client.server.id,
        userId: library.userId,
        itemId: itemId,
      );
      final ticks = localTicks ?? serverTicks;
      if (!mounted || generation != _openGeneration) return;
      final source = await library.client.playbackSource(
        library.userId,
        itemId,
        startPosition: Duration(microseconds: ticks ~/ 10),
      );
      if (!mounted || generation != _openGeneration) return;
      _client = library.client;
      _playbackSession = source.session;
      _serverId = library.client.server.id;
      _userId = library.userId;
      _progressItemId = itemId;
      _seriesId = item.seriesId;
      _runtimeTicks = item.runtime == null
          ? null
          : _durationToTicks(item.runtime!);
      _position = source.initialPosition;
      _initialPosition = source.initialPosition;
      _positionOffset = source.positionOffset;
      _pendingStartPosition = source.startPosition > Duration.zero
          ? source.startPosition
          : null;
      _fallbackStartSeekIssued = false;
      _fileLoadedAt = null;
      _completed = false;
      _pendingSubtitles = source.subtitles;
      _externalSubtitleLabel = context.l10n.externalSubtitle;
      _subtitlesAttached = false;
      _receivedPlayerPosition = false;
      await _player.open(
        Media(
          source.url,
          httpHeaders: source.headers,
          start: _pendingStartPosition,
        ),
        play: true,
      );
      if (!mounted || generation != _openGeneration) return;
      if (_player.state.duration > Duration.zero) {
        _fileLoadedAt ??= DateTime.now();
        await _onMediaLoaded(_player.state.duration, generation);
      }
      if (!mounted || generation != _openGeneration) return;
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
  }) => _progressRepository.tryLoad(
    serverId: serverId,
    userId: userId,
    itemId: itemId,
  );

  Future<void> _startTracking() async {
    _tracking = true;
    _stopped = false;
    _lastLocalSaveTicks = _positionTicks;
    _lastReportedTicks = _positionTicks;
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

    final rawTicks = _positionTicks;
    final runtime = _runtimeTicks ?? _durationToTicks(_player.state.duration);
    final finished =
        !failed &&
        (_completed || (runtime > 0 && rawTicks >= (runtime * 0.98).round()));
    final persistedTicks = finished ? 0 : rawTicks;
    final sessionTicks = finished && runtime > 0 ? runtime : rawTicks;
    final isPaused = !_playing;
    final volume = _player.state.volume;
    final revision = ++_progressRevision;
    final localSave = _serializeLocal(() async {
      try {
        await _progressRepository.save(
          serverId: serverId,
          userId: userId,
          itemId: itemId,
          positionTicks: persistedTicks,
        );
      } catch (error, stackTrace) {
        debugPrint('PLAYER_LOCAL_PROGRESS_WRITE_ERROR $error\n$stackTrace');
      }
    });

    if (!started && !report && !stopped) return localSave;
    _lastReportedTicks = rawTicks;
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
              position: Duration(microseconds: sessionTicks ~/ 10),
              failed: failed,
              volume: volume,
            );
          } else if (started) {
            await client.reportPlaybackStarted(
              session,
              position: Duration(microseconds: sessionTicks ~/ 10),
              isPaused: isPaused,
              volume: volume,
            );
          } else {
            await client.reportPlaybackProgress(
              session,
              position: Duration(microseconds: sessionTicks ~/ 10),
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
          position: Duration(microseconds: persistedTicks ~/ 10),
          played: finished ? true : null,
        );
        await _clearLocalIfCurrent(
          revision: revision,
          serverId: serverId,
          userId: userId,
          itemId: itemId,
          positionTicks: persistedTicks,
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

  Future<void> _exitPlayer({bool navigate = true}) async {
    if (_exiting) return;
    _exiting = true;
    _openGeneration++;
    final stopping = _stopTracking(failed: _error != null);
    if (!mounted) return;
    final refreshLibrary = ref.read(_refreshPlaybackProvider);
    final userId = _userId;
    final itemId = _progressItemId;
    final seriesId = _seriesId;
    void refresh() {
      refreshLibrary(userId, itemId, seriesId);
    }

    unawaited(
      _player.pause().catchError((Object error, StackTrace stackTrace) {
        debugPrint('PLAYER_PAUSE_ON_EXIT_ERROR $error\n$stackTrace');
      }),
    );
    leavePlayer(
      localSave: _localTail,
      serverSync: stopping,
      refresh: refresh,
      navigate: () {
        if (!navigate) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
    );
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

  Future<void> _setAudio(AudioTrack track, int generation) async {
    if (!mounted ||
        generation != _openGeneration ||
        _loading ||
        _switchingEpisode.value ||
        _exiting) {
      return;
    }
    if (track.id != 'auto' &&
        track.id != 'no' &&
        !_tracks.audio.contains(track)) {
      return;
    }
    try {
      await _player.setAudioTrack(track);
    } catch (error, stackTrace) {
      debugPrint('PLAYER_AUDIO_ERROR $error\n$stackTrace');
      if (mounted && generation == _openGeneration) {
        notifyUser(context, context.l10n.audioTrackError);
      }
    }
  }

  Future<void> _subtitleRenderingTail = Future.value();

  void _syncSubtitleRendering() {
    final generation = _openGeneration;
    _subtitleRenderingTail = _subtitleRenderingTail
        .then((_) async {
          if (!mounted || generation != _openGeneration) return;
          var selected = _track.subtitle;
          // media-kit keeps the auto sentinel rather than reporting mpv's
          // chosen subtitle track, so resolve it from the native player.
          if (selected.id == 'auto') {
            final id = await _nativePlayer.getProperty('sid');
            if (!mounted || generation != _openGeneration) return;
            selected = SubtitleTrack(id, null, null);
          }
          final native = usesNativeSubtitleRendering(
            selected,
            _tracks.subtitle,
          );
          await _nativePlayer.setProperty(
            'sub-visibility',
            native ? 'yes' : 'no',
          );
        })
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('PLAYER_SUBTITLE_RENDER_ERROR $error\n$stackTrace');
        });
  }

  Future<void> _setSubtitle(SubtitleTrack track) async {
    try {
      await _player.setSubtitleTrack(track);
    } catch (error, stackTrace) {
      debugPrint('PLAYER_SUBTITLE_ERROR $error\n$stackTrace');
      if (mounted) notifyUser(context, context.l10n.subtitleError);
    }
  }

  Future<void> _selectEpisode(MediaItem episode) async {
    if (_switchingEpisode.value ||
        _exiting ||
        episode.id == _currentItemId.value) {
      return;
    }
    _switchingEpisode.value = true;
    try {
      await _player.pause();
      await _stopTracking(failed: _error != null)
          .timeout(_exitSyncTimeout, onTimeout: () {});
      if (!mounted || _exiting) return;
      final userId = _userId;
      final previousId = _currentItemId.value;
      if (userId != null && previousId != null) {
        ref.invalidate(
          libraryItemProvider((userId: userId, itemId: previousId)),
        );
      }
      ref.invalidate(resumeItemsProvider);
      ref.invalidate(seriesEpisodesProvider);
      _currentItemId.value = episode.id;
      setState(() {});
      await _openMedia();
    } catch (error, stackTrace) {
      debugPrint('PLAYER_EPISODE_ERROR $error\n$stackTrace');
      if (mounted) notifyUser(context, failureMessage(context, error));
    } finally {
      if (mounted) _switchingEpisode.value = false;
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
    _controlsController.dispose();
    unawaited(_player.dispose());
    _currentItemId.dispose();
    _switchingEpisode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_exitPlayer(navigate: false));
      },
      child: ColoredBox(
        color: const Color(0xff000000),
        child: Stack(
          children: [
            Positioned.fill(
              child: Video(
                controller: _controller,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: false,
                ),
                controls: (state) => PlayerScreenshotSurface(
                  captureFrame: () => _player.screenshot(format: 'image/png'),
                  subtitles: PlayerSubtitles(player: _player),
                  controlsBuilder: (context, copyScreenshot) => PlayerControls(
                    onScreenshot: copyScreenshot,
                    controller: _controlsController,
                    gesturesEnabled: !_loading && !_exiting && _error == null,
                    onToggleFullscreen: state.toggleFullscreen,
                    onExitFullscreen: state.exitFullscreen,
                    fullscreen: state.isFullscreen(),
                    header: _buildHeader(item, () async {
                      if (state.isFullscreen()) await state.exitFullscreen();
                      await _exitPlayer();
                    }),
                    itemId: _currentItemId,
                    switching: _switchingEpisode,
                    onSelectEpisode: _selectEpisode,
                    topLeftOverlay:
                        _superResolutionMode == SuperResolutionMode.off
                        ? null
                        : const PlayerGpuUsage(),
                  ),
                ),
              ),
            ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(MediaItem? item, VoidCallback onBack) {
    final generation = _openGeneration;
    return Row(
      children: [
        FButton.icon(
          key: const ValueKey('player-back'),
          variant: .ghost,
          style: playerOverlayButtonStyle,
          size: .sm,
          onPress: onBack,
          semanticsLabel: context.l10n.back,
          child: const Icon(
            FLucideIcons.arrowLeft,
            size: 18,
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
        PlayerSuperResolutionMenu(
          mode: _superResolutionMode,
          onChanged: _setSuperResolution,
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<bool>(
          valueListenable: _switchingEpisode,
          builder: (context, switching, _) => PlayerAudioMenu(
            tracks: _tracks.audio,
            selected: _track.audio,
            enabled: !_loading && !switching && !_exiting,
            onChanged: (track) => _setAudio(track, generation),
          ),
        ),
        const SizedBox(width: 8),
        _SubtitleMenu(
          tracks: _tracks.subtitle,
          selected: _track.subtitle,
          onChanged: _setSubtitle,
        ),
      ],
    );
  }

  /// The item the route asked for, once the library session is available.
  MediaItem? get _item {
    final currentItemId = _currentItemId.value;
    if (currentItemId == null || currentItemId.isEmpty) return null;
    final userId = ref.watch(libraryViewsProvider).value?.userId;
    if (userId == null) return null;
    return ref
        .watch(libraryItemProvider((userId: userId, itemId: currentItemId)))
        .value;
  }

  String _title(MediaItem item) {
    final code = item.episodeCode;
    return code == null ? item.name : '$code · ${item.name}';
  }
}

class PlayerSuperResolutionMenu extends StatelessWidget {
  const PlayerSuperResolutionMenu({
    required this.mode,
    required this.onChanged,
    super.key,
  });

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
    builder: (context, controller, _) => FButton(
      key: const ValueKey('super-resolution-menu'),
      variant: .ghost,
      style: playerOverlayButtonStyle,
      size: .sm,
      onPress: controller.toggle,
      semanticsLabel: context.l10n.superResolution,
      mainAxisSize: MainAxisSize.min,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FLucideIcons.sparkles,
            size: 18,
            color: mode == SuperResolutionMode.off
                ? const Color(0xFFFFFFFF)
                : context.theme.colors.primary,
          ),
          if (mode != SuperResolutionMode.off) ...[
            const SizedBox(width: 6),
            Text(
              mode == SuperResolutionMode.efficiency
                  ? context.l10n.superResolutionEfficiencyActive
                  : context.l10n.superResolutionQualityActive,
              style: context.theme.typography.body.xs.copyWith(
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ],
        ],
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
    final labels = [
      for (var index = 0; index < choices.length; index++)
        formatSubtitleTrack(context.l10n, choices[index], index - 1),
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
                title: Text(
                  labels[index].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: labels[index].details == null
                    ? null
                    : Text(labels[index].details!),
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
        FItemGroup(
          children: [
            FItem(
              key: const ValueKey('subtitle-style'),
              title: Text(context.l10n.subtitleStyle),
              prefix: const Icon(FLucideIcons.slidersHorizontal, size: 16),
              onPress: () {
                controller.hide();
                unawaited(showSubtitleStyleDialog(context));
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        key: const ValueKey('subtitle-menu'),
        variant: .ghost,
        style: playerOverlayButtonStyle,
        size: .sm,
        onPress: controller.toggle,
        semanticsLabel: context.l10n.subtitles,
        child: Icon(
          selected.id == 'no'
              ? FLucideIcons.captionsOff
              : FLucideIcons.captions,
          size: 18,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}
