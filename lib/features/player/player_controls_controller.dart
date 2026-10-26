import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

abstract class PlayerControlsController extends ChangeNotifier {
  bool get playing;
  bool get buffering;
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
      player.stream.buffering.listen((_) => notifyListeners()),
      player.stream.position.listen((_) => notifyListeners()),
      player.stream.duration.listen((_) => notifyListeners()),
      player.stream.buffer.listen((_) => notifyListeners()),
      player.stream.volume.listen((_) => notifyListeners()),
    ]);
  }

  final Player player;
  final _subscriptions = <StreamSubscription<dynamic>>[];

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
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
