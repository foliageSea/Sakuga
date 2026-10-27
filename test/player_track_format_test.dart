import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/features/player/player_track_format.dart';
import 'package:sakuga/l10n/generated/app_localizations_en.dart';
import 'package:sakuga/l10n/generated/app_localizations_zh.dart';

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();

  test(
    'audio metadata retains titles and formats units without losing precision',
    () {
      const track = AudioTrack(
        '3',
        '  Original   mix  ',
        'jpn',
        codec: 'eac3',
        channels: '5.1(side)',
        samplerate: 44100,
        bitrate: 640000,
      );
      final label = formatAudioTrack(zh, track, 1);
      expect(label.title, 'Original mix');
      expect(label.details, '日语 · E-AC-3 · 5.1 · 44.1 kHz · 640 kbps');
      expect(
        formatAudioTrack(en, track, 1).details,
        'Japanese · E-AC-3 · 5.1 · 44.1 kHz · 640 kbps',
      );
    },
  );

  test(
    'missing titles use localized language without repeating it in details',
    () {
      const track = AudioTrack('7', ' ', 'ENG', codec: 'aac', channelscount: 2);
      expect(formatAudioTrack(zh, track, 2).title, '英语');
      expect(formatAudioTrack(zh, track, 2).details, 'AAC · 立体声');
      expect(formatAudioTrack(en, track, 2).title, 'English');
      expect(formatAudioTrack(en, track, 2).details, 'AAC · Stereo');
      const subtitle = SubtitleTrack('8', null, 'zh_Hant', codec: 'subrip');
      expect(formatSubtitleTrack(zh, subtitle, 1).title, '繁體中文');
      expect(
        formatSubtitleTrack(en, subtitle, 1).title,
        'Chinese (Traditional)',
      );
      expect(formatSubtitleTrack(zh, subtitle, 1).details, 'SRT');
    },
  );

  test(
    'absent or invalid metadata uses numbering and omits unusable values',
    () {
      const audio = AudioTrack(
        '9',
        null,
        'und',
        codec: '  ',
        channels: 'unknown',
        channelscount: 0,
        samplerate: -1,
        bitrate: 0,
      );
      expect(formatAudioTrack(zh, audio, 3).title, '音轨 3');
      expect(formatAudioTrack(zh, audio, 3).details, isNull);
      const subtitle = SubtitleTrack('10', ' ', 'zxx');
      expect(formatSubtitleTrack(en, subtitle, 4).title, 'Subtitle 4');
      expect(formatSubtitleTrack(en, subtitle, 4).details, isNull);
    },
  );

  test('unknown languages and regional variants remain distinguishable', () {
    expect(
      formatSubtitleTrack(en, const SubtitleTrack('2', null, 'en_US'), 1).title,
      'English (US)',
    );
    expect(
      formatSubtitleTrack(
        zh,
        const SubtitleTrack('3', null, 'zh-Hans-CN'),
        2,
      ).title,
      '简体中文 (CN)',
    );
    expect(
      formatSubtitleTrack(en, const SubtitleTrack('4', null, 'qaa'), 3).title,
      'qaa',
    );
  });

  test('channel count does not assume a surround layout', () {
    const audio = AudioTrack('1', null, null, channelscount: 6);
    expect(formatAudioTrack(zh, audio, 1).details, '6 声道');
    expect(formatAudioTrack(en, audio, 1).details, '6 channels');
    expect(
      formatAudioTrack(
        en,
        const AudioTrack('1', null, null, channels: 'mono'),
        1,
      ).details,
      'Mono',
    );
  });

  test('subtitle formats and external source are readable', () {
    final label = formatSubtitleTrack(
      zh,
      SubtitleTrack.uri(
        'https://example.com/sub.srt',
        title: 'Commentary',
        language: 'eng',
      ),
      1,
    );
    expect(label.title, 'Commentary');
    expect(label.details, '英语 · 外挂字幕');
    expect(
      formatSubtitleTrack(
        en,
        const SubtitleTrack('2', null, 'jpn', codec: 'hdmv_pgs_subtitle'),
        2,
      ).details,
      'PGS',
    );
    expect(
      formatSubtitleTrack(
        en,
        const SubtitleTrack('3', null, null, codec: 'ass'),
        3,
      ).details,
      'ASS',
    );
    expect(
      formatSubtitleTrack(
        en,
        const SubtitleTrack('4', null, null, codec: 'webvtt'),
        4,
      ).details,
      'WebVTT',
    );
  });

  test('automatic and off choices contain no technical metadata', () {
    expect(formatAudioTrack(zh, AudioTrack.auto(), 0).title, '自动选择');
    expect(formatAudioTrack(en, AudioTrack.no(), 0).title, 'Audio off');
    expect(formatSubtitleTrack(zh, SubtitleTrack.no(), 0).title, '关闭字幕');
    expect(formatSubtitleTrack(en, SubtitleTrack.auto(), 0).details, isNull);
  });
}
