import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../data/media_server/playback_models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/localization.dart';
import 'player_button_style.dart';

/// Bitrate caps offered to the user, in bits per second. "Maximum" (null)
/// keeps the default negotiation limit and prefers direct play.
const playbackBitratePresets = <int>[
  40000000,
  20000000,
  10000000,
  4000000,
  1500000,
  720000,
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

String playMethodLabel(AppLocalizations l10n, PlayMethod method) =>
    switch (method) {
      PlayMethod.directPlay => l10n.playMethodDirectPlay,
      PlayMethod.directStream => l10n.playMethodDirectStream,
      PlayMethod.transcode => l10n.playMethodTranscode,
    };

class PlayerQualityMenu extends StatelessWidget {
  const PlayerQualityMenu({
    required this.selected,
    required this.onChanged,
    this.playMethod,
    this.enabled = true,
    super.key,
  });

  /// Selected cap in bits per second; null means maximum quality.
  final int? selected;
  final PlayMethod? playMethod;
  final Future<void> Function(int? bitrate) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final choices = <int?>[null, ...playbackBitratePresets];
    final current = playMethod == null
        ? null
        : playMethodLabel(l10n, playMethod!);
    return FPopoverMenu(
      maxHeight: 420,
      menuAnchor: .topRight,
      childAnchor: .bottomRight,
      menuBuilder: (context, controller, _) => [
        FItemGroup(
          children: [
            for (final choice in choices)
              FItem(
                key: ValueKey('quality-${choice ?? 'max'}'),
                title: Text(
                  choice == null
                      ? l10n.playbackQualityMaximum
                      : formatBitrate(choice),
                ),
                subtitle: choice == selected && current != null
                    ? Text(current)
                    : null,
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
        FItemGroup(
          children: [
            FItem(
              key: const ValueKey('quality-hint'),
              enabled: false,
              title: Text(l10n.playbackQualityHint),
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
