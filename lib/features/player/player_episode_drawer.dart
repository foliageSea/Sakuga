import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/media_server/media_models.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/widgets.dart';
import '../detail/detail_providers.dart';

Future<void> showPlayerEpisodeDrawer(
  BuildContext context, {
  required String userId,
  required String seriesId,
  required ValueListenable<String?> itemId,
  required ValueListenable<bool> switching,
  required Future<void> Function(MediaItem) onSelect,
}) async {
  final selected = await showFSheet<MediaItem>(
    context: context,
    side: .rtl,
    useRootNavigator: true,
    mainAxisMaxRatio: 0.9,
    constraints: const BoxConstraints(maxWidth: 420),
    builder: (context) => DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.background,
        border: Border(left: BorderSide(color: context.theme.colors.border)),
      ),
      child: SizedBox(
        key: const ValueKey('player-episodes-drawer'),
        width: 420,
        height: double.infinity,
        child: SafeArea(
          left: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.selectEpisode,
                        style: context.theme.typography.body.lg.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FButton.icon(
                      key: const ValueKey('player-episodes-close'),
                      variant: .ghost,
                      size: .sm,
                      semanticsLabel: context.l10n.close,
                      onPress: () => Navigator.of(context).pop(),
                      child: const Icon(FLucideIcons.x),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                                      builder: (context, busy, _) =>
                                          _EpisodeList(
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
      final theme = context.theme;
      final titleStyle = theme.typography.body.sm;
      final subtitleStyle = theme.typography.body.xs;
      final scaler = MediaQuery.textScalerOf(context);
      final coverWidth = constraints.maxWidth < 340 ? 88.0 : 112.0;
      final coverHeight = coverWidth * 9 / 16;
      // Fixed row extents keep a late-loaded current episode immediately visible,
      // even in very long series. Reserve space for two title lines and metadata.
      final textHeight =
          scaler.scale(titleStyle.fontSize!) * (titleStyle.height ?? 1.4) * 2 +
          4 +
          scaler.scale(subtitleStyle.fontSize!) * (subtitleStyle.height ?? 1.4);
      final extent = math.max(coverHeight, textHeight) + 24;
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
          final runtime = episode.runtime;
          final metadata = [
            ?episode.episodeCode,
            if (runtime != null && runtime > Duration.zero)
              context.l10n.libraryDuration(runtime.inMinutes),
          ].join(' · ');
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FItemGroup(
              style: const .delta(spacing: 0),
              children: [
                FItem(
                  key: ValueKey('player-episode-${episode.id}'),
                  style: .delta(
                    backgroundColor: .delta([
                      .all(
                        current
                            ? theme.colors.secondary
                            : const Color(0x00000000),
                      ),
                    ]),
                    contentDecoration: .delta([
                      .all(
                        .shapeDelta(
                          color: current
                              ? theme.colors.secondary
                              : const Color(0x00000000),
                        ),
                      ),
                    ]),
                    contentStyle: const .delta(
                      suffixedPadding: .value(
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      unsuffixedPadding: .value(
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                  ),
                  prefix: SizedBox(
                    width: coverWidth,
                    height: coverHeight,
                    child: ClipRRect(
                      borderRadius: theme.style.borderRadius.sm,
                      child: MediaImage(
                        key: ValueKey('player-episode-cover-${episode.id}'),
                        url: episode.poster?.url(width: 320),
                        headers: episode.poster?.headers ?? const {},
                      ),
                    ),
                  ),
                  title: Text(
                    episode.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle.copyWith(
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle: metadata.isEmpty
                      ? null
                      : Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                  selected: current,
                  suffix: current
                      ? Icon(
                          FLucideIcons.play,
                          size: 16,
                          color: theme.colors.primary,
                        )
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
