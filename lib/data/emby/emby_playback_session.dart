import '../media_browser/media_browser_playback_session.dart';

class EmbyPlaybackSession extends MediaBrowserPlaybackSession {
  const EmbyPlaybackSession({
    required super.itemId,
    required super.mediaSourceId,
    required super.playSessionId,
    required super.playMethod,
  });
}
