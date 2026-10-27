import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';

import '../../shared/localization.dart';

class PlayerAudioMenu extends StatelessWidget {
  const PlayerAudioMenu({
    required this.tracks,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<AudioTrack> tracks;
  final AudioTrack selected;
  final Future<void> Function(AudioTrack track) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final available = tracks
        .where((track) => track.id != 'no' && track.id != 'auto')
        .toList();
    final choices = <AudioTrack>[
      AudioTrack.auto(),
      AudioTrack.no(),
      ...available,
    ];
    return FPopoverMenu(
      maxHeight: 420,
      menuAnchor: .topRight,
      childAnchor: .bottomRight,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (var index = 0; index < choices.length; index++)
              FItem(
                key: ValueKey('audio-${choices[index].id}'),
                title: Text(_label(context, choices[index], index)),
                subtitle: _details(choices[index]),
                selected: selected.id == choices[index].id,
                suffix: selected.id == choices[index].id
                    ? const Icon(FLucideIcons.check, size: 16)
                    : null,
                onPress: () {
                  controller.hide();
                  unawaited(onChanged(choices[index]));
                },
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        key: const ValueKey('audio-menu'),
        variant: .ghost,
        size: .sm,
        onPress: enabled && available.isNotEmpty ? controller.toggle : null,
        semanticsLabel: available.isEmpty
            ? context.l10n.noAudioTracks
            : context.l10n.audioTracks,
        child: const Icon(
          FLucideIcons.audioLines,
          size: 18,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }

  String _label(BuildContext context, AudioTrack track, int index) {
    if (track.id == 'auto') return context.l10n.audioAutomatic;
    if (track.id == 'no') return context.l10n.audioOff;
    final title = track.title?.trim();
    return title == null || title.isEmpty
        ? '${context.l10n.audioTrack} ${index - 1}'
        : title;
  }

  Widget? _details(AudioTrack track) {
    final parts = [track.language, track.codec]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }
}
