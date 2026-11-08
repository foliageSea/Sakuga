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
