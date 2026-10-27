import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

import '../../l10n/generated/app_localizations.dart';

/// Human-readable metadata shared by the audio and subtitle menus.
class PlayerTrackLabel {
  const PlayerTrackLabel(this.title, [this.details]);

  final String title;
  final String? details;
}

PlayerTrackLabel formatAudioTrack(
  AppLocalizations l,
  AudioTrack track,
  int number,
) {
  if (track.id == 'auto') return PlayerTrackLabel(l.audioAutomatic);
  if (track.id == 'no') return PlayerTrackLabel(l.audioOff);
  final language = _language(l, track.language);
  final title = _text(track.title) ?? language ?? '${l.audioTrack} $number';
  return PlayerTrackLabel(
    title,
    _details([
      if (language != title) language,
      _codec(track.codec),
      _channels(l, track),
      if (track.samplerate case final rate? when rate > 0)
        '${_number(l, rate / 1000)} kHz',
      if (track.bitrate case final rate? when rate > 0)
        '${_number(l, rate / 1000)} kbps',
    ]),
  );
}

PlayerTrackLabel formatSubtitleTrack(
  AppLocalizations l,
  SubtitleTrack track,
  int number,
) {
  if (track.id == 'auto') return PlayerTrackLabel(l.subtitlesAutomatic);
  if (track.id == 'no') return PlayerTrackLabel(l.subtitlesOff);
  final language = _language(l, track.language);
  final title = _text(track.title) ?? language ?? '${l.subtitleTrack} $number';
  return PlayerTrackLabel(
    title,
    _details([
      if (language != title) language,
      _codec(track.codec),
      if (track.uri || track.data) l.externalSubtitle,
    ]),
  );
}

String? _text(String? value) {
  final result = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return result == null || result.isEmpty ? null : result;
}

String? _details(List<String?> parts) {
  final values = parts.whereType<String>().toSet();
  return values.isEmpty ? null : values.join(' · ');
}

String _number(AppLocalizations l, num value) =>
    NumberFormat('0.###', l.localeName).format(value);

String? _language(AppLocalizations l, String? value) {
  final raw = _text(value);
  if (raw == null) return null;
  final tag = raw.toLowerCase().replaceAll('_', '-');
  if (['und', 'unknown', 'zxx'].contains(tag)) return null;
  final parts = tag.split('-');
  final name = switch (parts.first) {
    'zh' || 'zho' || 'chi' || 'chs' || 'cht' || 'cmn' => switch (tag) {
      'chs' => l.trackLanguageChineseSimplified,
      'cht' => l.trackLanguageChineseTraditional,
      _ when parts.contains('hans') => l.trackLanguageChineseSimplified,
      _ when parts.contains('hant') => l.trackLanguageChineseTraditional,
      _ => l.trackLanguageChinese,
    },
    'ja' || 'jpn' => l.trackLanguageJapanese,
    'en' || 'eng' => l.trackLanguageEnglish,
    'ko' || 'kor' => l.trackLanguageKorean,
    'yue' => l.trackLanguageCantonese,
    'fr' || 'fra' || 'fre' => l.trackLanguageFrench,
    'de' || 'deu' || 'ger' => l.trackLanguageGerman,
    'es' || 'spa' => l.trackLanguageSpanish,
    'pt' || 'por' => l.trackLanguagePortuguese,
    'ru' || 'rus' => l.trackLanguageRussian,
    'it' || 'ita' => l.trackLanguageItalian,
    'ar' || 'ara' => l.trackLanguageArabic,
    'th' || 'tha' => l.trackLanguageThai,
    'vi' || 'vie' => l.trackLanguageVietnamese,
    _ => null,
  };
  if (name == null) return raw;
  // Preserve regional distinctions without guessing a script from a region.
  final qualifiers = parts
      .skip(1)
      .where((part) => part != 'hans' && part != 'hant')
      .map((part) => part.toUpperCase());
  return qualifiers.isEmpty ? name : '$name (${qualifiers.join('-')})';
}

String? _codec(String? value) {
  final codec = _text(value);
  if (codec == null) return null;
  return switch (codec.toLowerCase()) {
    'ac3' || 'ac-3' => 'AC-3',
    'eac3' || 'e-ac-3' => 'E-AC-3',
    'truehd' => 'TrueHD',
    'subrip' || 'srt' => 'SRT',
    'webvtt' || 'vtt' => 'WebVTT',
    'hdmv_pgs_subtitle' || 'pgs' => 'PGS',
    'dvd_subtitle' || 'vobsub' => 'VobSub',
    'dvb_subtitle' => 'DVB',
    'mov_text' => 'TX3G',
    _ => codec.toUpperCase(),
  };
}

String? _channels(AppLocalizations l, AudioTrack track) {
  final layout = _text(track.channels);
  if (layout != null && !['unknown', 'und'].contains(layout.toLowerCase())) {
    return switch (layout.toLowerCase()) {
      'mono' || '1.0' => l.trackMono,
      'stereo' || '2.0' => l.trackStereo,
      '5.1(side)' => '5.1',
      _ => layout,
    };
  }
  final count = track.channelscount ?? track.audiochannels;
  return switch (count) {
    1 => l.trackMono,
    2 => l.trackStereo,
    final count? when count > 0 => l.trackChannelCount(count),
    _ => null,
  };
}
