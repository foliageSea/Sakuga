/// Adapter-owned state passed back to the client that created it.
abstract interface class PlaybackSession {}

enum PlayMethod { directPlay, directStream, transcode }

/// Upper bound used when the user has not limited playback quality.
const defaultMaxStreamingBitrate = 120000000;

class PlaybackSource {
  const PlaybackSource({
    required this.url,
    required this.headers,
    required this.session,
    this.startPosition = Duration.zero,
    Duration? initialPosition,
    this.positionOffset = Duration.zero,
    this.subtitles = const [],
    this.playMethod = PlayMethod.directPlay,
  }) : initialPosition = initialPosition ?? startPosition;
  final String url;
  final PlayMethod playMethod;
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
