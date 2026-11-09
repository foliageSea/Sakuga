import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../shared/localization.dart';
import 'player_button_style.dart';

/// A resolution and bitrate cap requested from the server.
class PlaybackQuality {
  const PlaybackQuality(this.height, this.bitrate);

  final int height;

  /// Bits per second.
  final int bitrate;

  String get label => '${height}p (${formatBitrate(bitrate)})';

  @override
  bool operator ==(Object other) =>
      other is PlaybackQuality &&
      other.height == height &&
      other.bitrate == bitrate;

  @override
  int get hashCode => Object.hash(height, bitrate);
}

/// Caps offered to the user. "Maximum" (null) keeps the default negotiation
/// limits and prefers direct play.
const playbackQualityPresets = <PlaybackQuality>[
  PlaybackQuality(1080, 20000000),
  PlaybackQuality(720, 8000000),
  PlaybackQuality(480, 3000000),
  PlaybackQuality(360, 1000000),
];

String formatBitrate(int bitsPerSecond) {
  if (bitsPerSecond >= 1000000) {
    final value = bitsPerSecond / 1000000;
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$text Mbps';
  }
  return '${(bitsPerSecond / 1000).round()} kbps';
}

class PlayerQualityMenu extends StatelessWidget {
  const PlayerQualityMenu({
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  /// Selected cap; null means maximum quality.
  final PlaybackQuality? selected;
  final Future<void> Function(PlaybackQuality? quality) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final choices = <PlaybackQuality?>[null, ...playbackQualityPresets];
    return FPopoverMenu(
      maxHeight: 420,
      menuAnchor: .topRight,
      childAnchor: .bottomRight,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (final choice in choices)
              FItem(
                key: ValueKey('quality-${choice?.height ?? 'max'}'),
                title: Text(choice?.label ?? l10n.playbackQualityMaximum),
                selected: choice == selected,
                suffix: choice == selected
                    ? const Icon(FLucideIcons.check, size: 16)
                    : null,
                onPress: () {
                  controller.hide();
                  if (choice != selected) unawaited(onChanged(choice));
                },
              ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        key: const ValueKey('quality-menu'),
        variant: .ghost,
        style: playerOverlayButtonStyle,
        size: .sm,
        onPress: enabled ? controller.toggle : null,
        semanticsLabel: l10n.playbackQuality,
        child: const Icon(
          FLucideIcons.gauge,
          size: 18,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}
