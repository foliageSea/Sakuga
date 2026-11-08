import '../media_browser/media_browser_mapper.dart';

export '../media_browser/media_browser_mapper.dart' show MediaBrowserMapper;

typedef JellyfinMapper = MediaBrowserMapper;
Duration jellyfinDuration(int ticks) => mediaBrowserDuration(ticks);
int jellyfinTicks(Duration duration) => mediaBrowserTicks(duration);
