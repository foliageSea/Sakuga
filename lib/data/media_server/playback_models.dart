/// Adapter-owned state passed back to the client that created it.
abstract interface class PlaybackSession {}

enum PlayMethod { directPlay, directStream, transcode }

class PlaybackSource {
  const PlaybackSource({
    required this.url,
    required this.headers,
    required this.session,
    this.startPosition = Duration.zero,
    Duration? initialPosition,
    this.positionOffset = Duration.zero,
    this.subtitles = const [],
  }) : initialPosition = initialPosition ?? startPosition;
  final String url;
  final Map<String, String> headers;
  final PlaybackSession session;
  final Duration initialPosition;
  final Duration positionOffset;
  final Duration startPosition;
  final List<SubtitleSource> subtitles;
}

class SubtitleSource {
  const SubtitleSource({required this.url, this.title, this.language});
  final String url;
  final String? title;
  final String? language;
}
