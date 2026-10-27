import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

abstract class PlayerControlsController extends ChangeNotifier {
  bool get playing;
  bool get buffering;

  /// Current media download rate in bytes per second, if available.
  double? get downloadBytesPerSecond;
  Duration get position;
  Duration get duration;
  Duration get buffer;
  double get volume;
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
}

class MediaKitControlsController extends PlayerControlsController {
  MediaKitControlsController(this.player) {
    _subscriptions.addAll([
      player.stream.playing.listen((_) => notifyListeners()),
      player.stream.buffering.listen(_onBufferingChanged),
      player.stream.position.listen((_) => notifyListeners()),
      player.stream.duration.listen((_) => notifyListeners()),
      player.stream.buffer.listen((_) => notifyListeners()),
      player.stream.volume.listen((_) => notifyListeners()),
    ]);
    _onBufferingChanged(player.state.buffering);
  }

  final Player player;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _downloadSpeedTimer;
  double? _downloadBytesPerSecond;
  bool _readingDownloadSpeed = false;
  bool _disposed = false;
  int _bufferingGeneration = 0;

  void _onBufferingChanged(bool buffering) {
    _bufferingGeneration++;
    _downloadSpeedTimer?.cancel();
    _downloadSpeedTimer = null;
    _downloadBytesPerSecond = null;
    if (buffering && player.platform is NativePlayer) {
      unawaited(_readDownloadSpeed());
      _downloadSpeedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(_readDownloadSpeed());
      });
    }
    notifyListeners();
  }

  Future<void> _readDownloadSpeed() async {
    if (_disposed || _readingDownloadSpeed) return;
    final platform = player.platform;
    if (platform is! NativePlayer) return;
    final generation = _bufferingGeneration;
    _readingDownloadSpeed = true;
    double? speed;
    try {
      // mpv reports the media cache's actual read rate in bytes per second.
      final value = double.tryParse(await platform.getProperty('cache-speed'));
      if (value != null && value.isFinite && value >= 0) speed = value;
    } catch (_) {
      // Statistics may be unavailable while a file opens or closes.
    } finally {
      _readingDownloadSpeed = false;
    }
    if (_disposed || generation != _bufferingGeneration) return;
    if (_downloadBytesPerSecond != speed) {
      _downloadBytesPerSecond = speed;
      notifyListeners();
    }
  }

  @override
  double? get downloadBytesPerSecond => _downloadBytesPerSecond;

  @override
  bool get playing => player.state.playing;
  @override
  bool get buffering => player.state.buffering;
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration => player.state.duration;
  @override
  Duration get buffer => player.state.buffer;
  @override
  double get volume => player.state.volume;
  @override
  Future<void> playOrPause() => player.playOrPause();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> setVolume(double volume) => player.setVolume(volume);

  @override
  void dispose() {
    _disposed = true;
    _downloadSpeedTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
