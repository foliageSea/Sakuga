import '../media_server/playback_models.dart';

abstract class MediaBrowserPlaybackSession implements PlaybackSession {
  const MediaBrowserPlaybackSession({
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.playMethod,
  });
  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final PlayMethod playMethod;
}
