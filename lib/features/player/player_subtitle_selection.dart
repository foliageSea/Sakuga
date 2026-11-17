import 'package:media_kit/media_kit.dart';

/// Returns the preferred Chinese subtitle, or null when none is identifiable.
///
/// Simplified (including bilingual) > unspecified Chinese > traditional.
/// Within each language tier ASS/SSA wins; otherwise input order is preserved.
/// Explicit language scripts/regions take precedence over title hints. Titles
/// may refine generic Chinese or identify mislabeled bilingual subtitles, but a
/// generic Chinese title never overrides an explicitly non-Chinese language.
SubtitleTrack? preferredChineseSubtitle(Iterable<SubtitleTrack> tracks) {
  SubtitleTrack? preferred;
  var bestRank = -1;
  for (final track in tracks) {
    if (track.id == 'auto' || track.id == 'no') continue;
    final tier = _chineseTier(track);
    if (tier == null) continue;
    final codec = track.codec?.trim().toLowerCase();
    final rank = tier * 2 + (codec == 'ass' || codec == 'ssa' ? 1 : 0);
    if (rank > bestRank) {
      preferred = track;
      bestRank = rank;
    }
  }
  return preferred;
}

const _traditional = 0;
const _generic = 1;
const _simplified = 2;

int? _chineseTier(SubtitleTrack track) {
  final language = track.language?.trim().toLowerCase().replaceAll('_', '-');
  final parts = language?.split('-') ?? const <String>[];
  final base = parts.isEmpty ? '' : parts.first;
  final isChinese = const {'zh', 'zho', 'chi', 'cmn'}.contains(base);

  if (base == 'chs') return _simplified;
  if (base == 'cht') return _traditional;
  if (isChinese) {
    // A script is more precise than a region, e.g. zh-Hant-CN.
    for (final part in parts.skip(1)) {
      if (part == 'hans') return _simplified;
      if (part == 'hant') return _traditional;
    }
    for (final part in parts.skip(1)) {
      if (part == 'cn' || part == 'sg') return _simplified;
      if (part == 'tw' || part == 'hk' || part == 'mo') {
        return _traditional;
      }
    }
  }

  final title = track.title ?? '';
  if (_simplifiedTitle.hasMatch(title)) return _simplified;
  if (_traditionalTitle.hasMatch(title)) return _traditional;
  if (isChinese) return _generic;

  final languageMissing = const {'', 'und', 'unknown', 'zxx'}.contains(base);
  if (languageMissing && _chineseTitle.hasMatch(title)) return _generic;
  return null;
}

// English tokens have word boundaries: "CHS" is a marker, "yachts" is not.
// Chinese markers deliberately allow adjacency, as in "简日双语字幕".
final _simplifiedTitle = RegExp(
  r'简体|简中|簡體|簡中|简日|简英|簡日|簡英|'
  r'\b(?:chs|gb(?:2312|18030)?|simplified[\s_-]+chinese|'
  r'chinese[\s_-]+simplified)\b',
  caseSensitive: false,
);
final _traditionalTitle = RegExp(
  r'繁体|繁中|繁體|繁日|繁英|'
  r'\b(?:cht|big5|traditional[\s_-]+chinese|'
  r'chinese[\s_-]+traditional)\b',
  caseSensitive: false,
);
final _chineseTitle = RegExp(
  r'中文|中日|中英|汉语|漢語|华语|華語|\bchinese\b',
  caseSensitive: false,
);
