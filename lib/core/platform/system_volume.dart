import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android media stream volume, expressed as a percentage of its native range.
class SystemVolume extends ChangeNotifier {
  SystemVolume() {
    // The native stream sends the current volume as soon as it is subscribed.
    _subscription = _events.receiveBroadcastStream().listen(
      (value) => _update((value as num).toDouble()),
      onError: (Object error) => debugPrint('SYSTEM_VOLUME_ERROR $error'),
    );
  }

  static const channel = MethodChannel('com.foliage.sakuga/system_volume');
  static const _events = EventChannel(
    'com.foliage.sakuga/system_volume/changes',
  );

  late final StreamSubscription<dynamic> _subscription;
  double _volume = 100;
  bool _disposed = false;

  double get volume => _volume;

  Future<void> setVolume(double value) async {
    final actual = await channel.invokeMethod<double>(
      'set',
      value.clamp(0.0, 100.0),
    );
    if (actual != null) _update(actual);
  }

  void _update(double value) {
    if (_disposed || !value.isFinite) return;
    final volume = value.clamp(0.0, 100.0);
    if (_volume == volume) return;
    _volume = volume;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
