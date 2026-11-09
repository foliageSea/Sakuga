import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'player_subtitles.dart';

/// Enable libass at player creation, including Android's required fallback font.
const subtitlePlayerConfiguration = PlayerConfiguration(
  libass: true,
  libassAndroidFont: 'assets/MiSans-Regular.ttf',
  libassAndroidFontName: 'MiSans',
);

/// Serializes native visibility changes and hides Flutter captions until the
/// actual mpv track is known. This also handles media-kit's `auto`/URI sentinels.
class SubtitleRenderingController extends ChangeNotifier {
  SubtitleRenderingController({
    required this.getProperty,
    required this.setProperty,
  });

  final Future<String> Function(String name) getProperty;
  final Future<void> Function(String name, String value) setProperty;
  Future<void> _tail = Future.value();
  int _revision = 0;
  bool _disposed = false;
  bool _flutterVisible = false;
  bool _native = true;

  bool get flutterVisible => _flutterVisible;
  bool get nativeRendering => _native;

  void reset() {
    _revision++;
    _flutterVisible = false;
    _native = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> synchronize(
    SubtitleTrack selected,
    List<SubtitleTrack> available,
  ) {
    final revision = ++_revision;
    _flutterVisible = false;
    if (!_disposed) notifyListeners();
    bool current() => !_disposed && revision == _revision;
    final next = _tail.then((_) async {
      if (!current()) return;
      final id = selected.id == 'no' ? 'no' : await getProperty('sid');
      if (!current()) return;
      final disabled = id == 'no' || id == '0' || id.isEmpty;
      SubtitleTrack track = SubtitleTrack(id, null, null);
      for (final candidate in available) {
        if (candidate.id == id) {
          track = candidate;
          break;
        }
      }
      if (!disabled && track.codec == null && track.image != true) {
        // Track events can precede metadata; query mpv rather than briefly
        // flattening an ASS track or trusting an external subtitle's extension.
        final count = int.tryParse(await getProperty('track-list/count')) ?? 0;
        if (!current()) return;
        for (var index = 0; index < count; index++) {
          final prefix = 'track-list/$index';
          final type = await getProperty('$prefix/type');
          if (!current()) return;
          if (type != 'sub') continue;
          final candidateId = await getProperty('$prefix/id');
          if (!current()) return;
          if (candidateId != id) continue;
          final codec = await getProperty('$prefix/codec');
          if (!current()) return;
          track = SubtitleTrack(
            id,
            null,
            null,
            codec: codec.isEmpty ? null : codec,
          );
          break;
        }
      }
      // Unknown codecs stay native; do not silently destroy authored styling.
      final native =
          !disabled &&
          (track.codec == null || usesNativeSubtitleRendering(track, [track]));
      await setProperty('sub-visibility', native ? 'yes' : 'no');
      if (!current()) return;
      _native = native;
      _flutterVisible = !disabled && !native;
      notifyListeners();
    });
    // Recover the queue after a failed property request; the caller logs it.
    _tail = next.catchError((Object _) {});
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
