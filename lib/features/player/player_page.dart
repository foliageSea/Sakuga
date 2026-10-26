import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/jellyfin/jellyfin_models.dart';
import '../../shared/localization.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';

/// Full-screen player shell. Media negotiation and controls arrive in M2.
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({this.itemId, super.key});

  /// The Jellyfin item to play. Null on the dev route, which plays
  /// [DEV_MEDIA_URL] instead of a library item.
  final String? itemId;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  static const _devMediaUrl = String.fromEnvironment('DEV_MEDIA_URL');

  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    debugPrint('DEV_PLAYER url=$_devMediaUrl item=${widget.itemId}');
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
    final item = _item;
    return ColoredBox(
      color: const Color(0xff000000),
      child: Stack(
        children: [
          Positioned.fill(child: Video(controller: _controller)),
          Positioned(
            left: 12,
            top: 12,
            right: 12,
            child: SafeArea(
              child: Row(
                children: [
                  FButton.icon(
                    key: const ValueKey('player-back'),
                    variant: .ghost,
                    onPress: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                    semanticsLabel: context.l10n.back,
                    child: const Icon(
                      FLucideIcons.arrowLeft,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  if (item != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _title(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.md.copyWith(
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The item the route asked for, once the library session is available. M2
  /// uses it to negotiate the stream.
  JellyfinItem? get _item {
    final itemId = widget.itemId;
    if (itemId == null || itemId.isEmpty) return null;
    final userId = ref.watch(libraryViewsProvider).value?.userId;
    if (userId == null) return null;
    return ref
        .watch(libraryItemProvider((userId: userId, itemId: itemId)))
        .value;
  }

  String _title(JellyfinItem item) {
    final code = item.episodeCode;
    return code == null ? item.name : '$code · ${item.name}';
  }
}
