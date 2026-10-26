import 'dart:async';

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
  static const _devMediaUrl = String.fromEnvironment('DEV_MEDIA_URL');

  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    debugPrint('DEV_PLAYER url=$_devMediaUrl');
    if (_devMediaUrl.isNotEmpty) {
      _player.stream.playing.listen(
        (playing) => debugPrint('DEV_PLAYING $playing'),
      );
      _player.stream.position.listen(
        (position) => debugPrint('DEV_POSITION ${position.inMilliseconds}'),
      );
      _player.stream.error.listen((error) => debugPrint('DEV_ERROR $error'));
      unawaited(_openDevMedia());
    }
  }

  Future<void> _openDevMedia() async {
    await _player.open(Media(_devMediaUrl), play: true);
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
