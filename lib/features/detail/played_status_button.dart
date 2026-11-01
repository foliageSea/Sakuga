import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../data/media_server/media_models.dart';
import '../../data/media_server/media_server_client.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../home/home_providers.dart';
import '../library/library_providers.dart';
import '../player/playback_progress_repository.dart';
import 'detail_providers.dart';

// Keep the refresh callback alive for the container's lifetime so navigation
// away from the detail route does not leave the home list stale.
final _refreshPlayedItemsProvider = Provider((ref) {
  return (MediaServerClient client, String userId) {
    if (!ref.mounted) return;
    final library = ref.read(libraryViewsProvider).value;
    if (ref.read(activeServerProvider) != client.server ||
        library?.client != client ||
        library?.userId != userId) {
      return;
    }
    ref.invalidate(libraryItemProvider);
    ref.invalidate(seriesEpisodesProvider);
    ref.invalidate(seriesSeasonsProvider);
    ref.invalidate(libraryItemsProvider);
    ref.invalidate(resumeItemsProvider);
    ref.invalidate(latestItemsProvider);
  };
});

/// Updates one playable item's status, keeping pending progress and cached lists
/// consistent with the explicit server action.
class PlayedStatusButton extends ConsumerStatefulWidget {
  const PlayedStatusButton({
    required this.client,
    required this.userId,
    required this.item,
    this.iconOnly = false,
    super.key,
  });

  final MediaServerClient client;
  final String userId;
  final MediaItem item;
  final bool iconOnly;

  @override
  ConsumerState<PlayedStatusButton> createState() => _PlayedStatusButtonState();
}

class _PlayedStatusButtonState extends ConsumerState<PlayedStatusButton> {
  bool _busy = false;
  bool _confirming = false;
  bool? _played;
  Object? _error;

  @override
  void didUpdateWidget(covariant PlayedStatusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.userId != widget.userId ||
        oldWidget.item.id != widget.item.id) {
      _played = null;
      _error = null;
    } else if (oldWidget.item.played != widget.item.played) {
      _played = null;
    }
  }

  Future<void> _toggle() async {
    if (_busy || _confirming) return;
    final client = widget.client;
    final server = client.server;
    final userId = widget.userId;
    final itemId = widget.item.id;
    final played = widget.iconOnly || !(_played ?? widget.item.played);
    if (played) {
      setState(() => _confirming = true);
      bool? confirmed;
      try {
        confirmed = await _confirmPlayed(
          widget.item.displayTitle,
          episode: widget.item.displaySubtitle,
        );
      } finally {
        if (mounted) setState(() => _confirming = false);
      }
      if (confirmed != true ||
          !_matches(client, userId, itemId) ||
          ref.read(activeServerProvider) != server) {
        return;
      }
    }
    final repository = ref.read(playbackProgressRepositoryProvider);
    final refresh = ref.read(_refreshPlayedItemsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Capture the old checkpoint before the request so a new save made while
      // the request is in flight is preserved by conditional removal.
      final pending = await repository.load(
        serverId: server.id,
        userId: userId,
        itemId: itemId,
      );
      await client.setPlayed(userId, itemId, played: played);
      if (pending != null) {
        await repository.clearIfMatches(
          serverId: server.id,
          userId: userId,
          itemId: itemId,
          positionTicks: pending,
        );
      }
      refresh(client, userId);
      if (_matches(client, userId, itemId)) {
        setState(() => _played = played);
      }
    } catch (error) {
      if (_matches(client, userId, itemId)) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmPlayed(String name, {String? episode}) {
    final l = context.l10n;
    return showFDialog<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        animation: animation,
        builder: (context, style) => SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.markAsPlayed,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.markAsPlayedConfirm(
                  episode == null ? name : '$name · $episode',
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FButton(
                    key: const ValueKey('played-status-cancel'),
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    variant: .ghost,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(l.cancel),
                  ),
                  FButton(
                    key: const ValueKey('played-status-confirm'),
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(l.markAsPlayed),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _matches(MediaServerClient client, String userId, String itemId) =>
      mounted &&
      widget.client == client &&
      widget.userId == userId &&
      widget.item.id == itemId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final label = !widget.iconOnly && (_played ?? widget.item.played)
        ? l.markAsUnplayed
        : l.markAsPlayed;
    if (widget.iconOnly) {
      final hint = _error == null
          ? (_busy ? l.saving : label)
          : '${failureMessage(context, _error!)} ${l.retry}';
      return FTooltip(
        tipBuilder: (context, controller) => Text(hint),
        child: Semantics(
          liveRegion: _error != null,
          child: FButton.icon(
            key: ValueKey('played-status-${widget.item.id}'),
            variant: .ghost,
            size: .sm,
            onPress: _busy || _confirming ? null : _toggle,
            semanticsLabel: '${widget.item.name}: $hint',
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: FCircularProgress(),
                  )
                : Icon(
                    _error != null
                        ? FLucideIcons.circleAlert
                        : FLucideIcons.check,
                    color: _error != null
                        ? context.theme.colors.destructive
                        : const Color(0xFFFFFFFF),
                    shadows: const [
                      Shadow(color: Color(0xCC000000), blurRadius: 4),
                    ],
                  ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FButton(
          key: ValueKey('played-status-${widget.item.id}'),
          variant: .outline,
          mainAxisSize: MainAxisSize.min,
          builder: responsiveButtonContent,
          onPress: _busy || _confirming ? null : _toggle,
          semanticsLabel: '${widget.item.name}: $label',
          prefix: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: FCircularProgress(),
                )
              : Icon(
                  (_played ?? widget.item.played)
                      ? FLucideIcons.undo2
                      : FLucideIcons.check,
                ),
          child: Text(
            _busy ? l.saving : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: ErrorNotice(_error!)),
        ],
      ],
    );
  }
}
