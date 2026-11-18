import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../emby/emby_client.dart';
import '../emby/emby_probe.dart';
import '../fnmovie/fnmovie_client.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_probe.dart';
import 'media_server_client.dart';
import 'server_probe.dart';
import 'server_profile.dart';

class MediaServerFactory {
  const MediaServerFactory();
  MediaServerClient createClient(ServerProfile server) => switch (server.type) {
    MediaServerType.jellyfin => JellyfinClient(server: server),
    MediaServerType.emby => EmbyClient(server: server),
    MediaServerType.fnmovie => FnMovieClient(server: server),
  };
  ServerProbe createProbe(MediaServerType type) => switch (type) {
    MediaServerType.jellyfin => JellyfinProbe(),
    MediaServerType.emby => EmbyProbe(),
    MediaServerType.fnmovie => throw UnsupportedError(
      'fnOS Media requires account login',
    ),
  };
}

final mediaServerFactoryProvider = Provider<MediaServerFactory>(
  (ref) => const MediaServerFactory(),
);

// Playback may still be saving progress after route disposal.
final mediaServerClientProvider =
    Provider.family<MediaServerClient, ServerProfile>(
      (ref, server) =>
          ref.watch(mediaServerFactoryProvider).createClient(server),
    );

final serverProbeProvider = Provider.family<ServerProbe, MediaServerType>(
  (ref, type) => ref.watch(mediaServerFactoryProvider).createProbe(type),
);
