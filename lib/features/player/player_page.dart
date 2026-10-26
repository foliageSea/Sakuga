import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../shared/localization.dart';

/// Full-screen player shell. Media negotiation and controls arrive in M2.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff000000),
      child: Stack(
        children: [
          Positioned.fill(child: Video(controller: _controller)),
          Positioned(
            left: 12,
            top: 12,
            child: SafeArea(
              child: FButton.icon(
                variant: .ghost,
                onPress: () => context.pop(),
                semanticsLabel: context.l10n.back,
                child: const Icon(FLucideIcons.arrowLeft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
