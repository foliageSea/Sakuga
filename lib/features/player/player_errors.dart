import 'dart:async';

/// media_kit forwards every mpv error-level log line (decoder, audio output,
/// network retries, ...) through the error stream, and many of them are
/// recoverable. An error only counts as a playback failure once mpv has
/// actually stopped the file; with `keep-open` a normal end keeps it loaded.
class PlaybackErrorGate {
  PlaybackErrorGate({
    required this.isStopped,
    required this.onFatal,
    this.delay = const Duration(milliseconds: 1500),
  });

  final Future<bool> Function() isStopped;
  final void Function(String error) onFatal;
  final Duration delay;
  Timer? _timer;
  int _revision = 0;

  void report(String error) {
    final revision = ++_revision;
    _timer?.cancel();
    _timer = Timer(delay, () async {
      bool stopped;
      try {
        stopped = await isStopped();
      } catch (_) {
        // Without a native answer, keep the previous behavior and report it.
        stopped = true;
      }
      if (revision == _revision && stopped) onFatal(error);
    });
  }

  /// Drops pending checks, e.g. when new media opens or the player closes.
  void reset() {
    _revision++;
    _timer?.cancel();
    _timer = null;
  }
}

/// Whether mpv has given up on the current file: nothing is loaded (load or
/// playback failure), or it hit the end well before the media duration, which
/// is how a dropped stream ends under `keep-open`.
bool isPlaybackAborted({
  required bool idle,
  required bool endReached,
  required Duration position,
  required Duration duration,
}) {
  if (idle) return true;
  return endReached &&
      duration > Duration.zero &&
      position < duration - const Duration(seconds: 5);
}

/// Native errors may include authenticated media/subtitle URLs.
String redactPlaybackError(
  Object error, {
  Iterable<String> secrets = const [],
}) {
  var message = error.toString().replaceAll(
    RegExp(r'https?://[^\s<>"]+'),
    '[media URL]',
  );
  for (final secret in secrets) {
    if (secret.isEmpty) continue;
    message = message
        .replaceAll(secret, '[redacted]')
        .replaceAll(Uri.encodeQueryComponent(secret), '[redacted]');
  }
  return message;
}

/// Whether mpv failed to open one of the external subtitle resources attached
/// to the current media. These errors do not mean the video failed to play.
bool isExternalSubtitleLoadError(String error, Iterable<String> subtitleUrls) {
  final message = error.trim();
  for (final url in subtitleUrls) {
    if (url.isEmpty) continue;
    for (final prefix in ['Failed to open ', 'Can not open external file ']) {
      if (message == '$prefix$url' || message == '$prefix$url.') return true;
    }
  }
  return false;
}
