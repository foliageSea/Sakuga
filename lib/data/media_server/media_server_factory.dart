import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/jellyfin_probe.dart';
import 'media_server_client.dart';
import 'server_probe.dart';
import 'server_profile.dart';

class MediaServerFactory {
  const MediaServerFactory();
  MediaServerClient createClient(ServerProfile server) => switch (server.type) {
    MediaServerType.jellyfin => JellyfinClient(server: server),
  };
  ServerProbe createProbe(MediaServerType type) => switch (type) {
    MediaServerType.jellyfin => JellyfinProbe(),
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
