import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/media_server/media_models.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';
import '../detail/detail_providers.dart';

Future<void> showPlayerEpisodeDialog(
  BuildContext context, {
  required String userId,
  required String seriesId,
  required ValueListenable<String?> itemId,
  required ValueListenable<bool> switching,
  required Future<void> Function(MediaItem) onSelect,
}) async {
  final selected = await showFDialog<MediaItem>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context, style, animation) => FDialog(
      key: const ValueKey('player-episodes-dialog'),
      animation: animation,
      builder: (context, style) => SizedBox(
        height: math.min(520, MediaQuery.sizeOf(context).height * 0.7),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.selectEpisode,
                      style: context.theme.typography.body.lg,
                    ),
                  ),
                  FButton.icon(
                    variant: .ghost,
                    onPress: () => Navigator.of(context).pop(),
                    semanticsLabel: context.l10n.close,
                    child: const Icon(FLucideIcons.x, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final query = (
                      userId: userId,
                      seriesId: seriesId,
                      seasonId: null as String?,
                    );
                    final episodes = ref.watch(seriesEpisodesProvider(query));
                    return episodes.when(
                      loading: () => const Center(child: FCircularProgress()),
                      error: (error, _) => SingleChildScrollView(
                        child: ErrorNotice(
                          error,
                          onRetry: () =>
                              ref.invalidate(seriesEpisodesProvider(query)),
                        ),
                      ),
                      data: (values) => values.isEmpty
                          ? Center(child: Text(context.l10n.noItems))
                          : ValueListenableBuilder(
                              valueListenable: itemId,
                              builder: (context, currentId, _) =>
                                  ValueListenableBuilder(
                                    valueListenable: switching,
                                    builder: (context, busy, _) => _EpisodeList(
                                      key: ValueKey(currentId),
                                      episodes: values,
                                      currentId: currentId,
                                      busy: busy,
                                    ),
                                  ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (selected != null &&
      context.mounted &&
      !switching.value &&
      selected.id != itemId.value) {
    await onSelect(selected);
  }
}

class _EpisodeList extends StatefulWidget {
  const _EpisodeList({
    required this.episodes,
    required this.currentId,
    required this.busy,
    super.key,
  });

  final List<MediaItem> episodes;
  final String? currentId;
  final bool busy;

  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  ScrollController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titleStyle = context.theme.typography.body.sm;
      final extent = math.max(
        48.0,
        MediaQuery.textScalerOf(context).scale(titleStyle.fontSize!) *
                (titleStyle.height ?? 1.4) *
                2 +
            16,
      );
      final index = widget.episodes.indexWhere((e) => e.id == widget.currentId);
      final maxOffset = math.max(
        0.0,
        widget.episodes.length * extent - constraints.maxHeight,
      );
      _controller ??= ScrollController(
        initialScrollOffset:
            (math.max(0, index) * extent - (constraints.maxHeight - extent) / 2)
                .clamp(0, maxOffset),
      );
      return ListView.builder(
        key: const ValueKey('player-episodes-list'),
        controller: _controller,
        padding: EdgeInsets.zero,
        itemExtent: extent,
        itemCount: widget.episodes.length,
        itemBuilder: (context, index) {
          final episode = widget.episodes[index];
          final current = episode.id == widget.currentId;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: FItemGroup(
              style: const .delta(spacing: 0),
              children: [
                FItem(
                  key: ValueKey('player-episode-${episode.id}'),
                  style: .delta(
                    backgroundColor: .delta([.all(const Color(0x00000000))]),
                    contentDecoration: .delta([
                      .all(const .shapeDelta(color: Color(0x00000000))),
                    ]),
                    contentStyle: const .delta(
                      suffixedPadding: .value(
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      unsuffixedPadding: .value(
                        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ),
                  title: Text(
                    episode.displaySubtitle ?? episode.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: current,
                  suffix: current
                      ? const Icon(FLucideIcons.check, size: 16)
                      : null,
                  onPress: widget.busy
                      ? null
                      : () => Navigator.of(context).pop(episode),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
