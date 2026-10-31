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
