import '../../l10n/generated/app_localizations.dart';

String playbackBufferLabel(AppLocalizations l10n, int mib) {
  final name = switch (mib) {
    <= 32 => l10n.playbackBufferStandard,
    <= 128 => l10n.playbackBufferLarge,
    _ => l10n.playbackBufferExtraLarge,
  };
  return '$name · $mib MiB';
}

/// Already-played data mpv keeps for backward seeking. Kept at the previous
/// default so a larger forward buffer does not double the footprint.
const playbackBackBufferBytes = 32 * 1024 * 1024;

int playbackBufferBytes(int mib) => mib * 1024 * 1024;

/// Applies the user's forward buffer limit before a file is opened. mpv uses
/// these limits for the next demuxer, so changes take effect on the next open.
Future<void> applyPlaybackBuffer(
  Future<void> Function(String name, String value) setProperty,
  int mib,
) async {
  await setProperty('demuxer-max-bytes', '${playbackBufferBytes(mib)}');
  await setProperty('demuxer-max-back-bytes', '$playbackBackBufferBytes');
}
