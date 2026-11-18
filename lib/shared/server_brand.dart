import 'package:flutter/widgets.dart';

import '../data/media_server/server_profile.dart';
import 'localization.dart';

String serverTypeLabel(BuildContext context, MediaServerType type) =>
    switch (type) {
      MediaServerType.jellyfin => 'Jellyfin',
      MediaServerType.emby => 'Emby',
      MediaServerType.fnmovie => context.l10n.serverTypeFnMovie,
      MediaServerType.ugreen => context.l10n.serverTypeUgreen,
    };

class ServerTypeIcon extends StatelessWidget {
  const ServerTypeIcon({super.key, required this.type, required this.size});

  final MediaServerType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = type == MediaServerType.fnmovie ? 'fnos' : type.name;
    return Image.asset(
      'assets/icons/servers/$name.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
