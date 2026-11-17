import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sakuga/features/player/player_subtitle_selection.dart';

SubtitleTrack _track(
  String id, {
  String? language,
  String? title,
  String? codec,
  bool? image,
}) => SubtitleTrack(id, title, language, codec: codec, image: image);

void main() {
  group('preferredChineseSubtitle', () {
    test('returns null for empty input and unidentifiable tracks', () {
      expect(preferredChineseSubtitle([]), isNull);
      expect(
        preferredChineseSubtitle([
          _track('1'),
          _track('2', language: 'eng', codec: 'ass'),
          _track('3', language: 'jpn'),
          _track('4', language: 'und', title: 'Full subtitles'),
          _track('5', language: 'unknown'),
          _track('6', language: 'zhongwen'),
        ]),
        isNull,
      );
    });

    test('ignores automatic and off sentinel tracks even with metadata', () {
      final actual = _track('3', language: 'zh-Hant');
      final sentinels = [
        SubtitleTrack.auto(),
        SubtitleTrack.no(),
        _track('auto', language: 'zh-Hans', title: 'CHS', codec: 'ass'),
        _track('no', language: 'zh-Hans', title: 'CHS', codec: 'ass'),
      ];
      expect(preferredChineseSubtitle(sentinels), isNull);
      expect(preferredChineseSubtitle([...sentinels, actual]), same(actual));
    });

    for (final language in [
      'zh-Hans',
      'zh-CN',
      'zh-SG',
      'ZH_hAnS',
      ' zh_cn ',
      'chi-Hans',
      'zho-CN',
      'cmn-Hans',
      'chs',
      'CHS',
    ]) {
      test('recognizes simplified language $language before generic ASS', () {
        final simplified = _track('s', language: language);
        expect(
          preferredChineseSubtitle([
            _track('g', language: 'zh', codec: 'ass'),
            simplified,
          ]),
          same(simplified),
        );
      });
    }

    for (final language in [
      'zh-Hant',
      'zh-TW',
      'zh-HK',
      'zh-MO',
      'ZH_hAnT',
      'chi-TW',
      'zho-HK',
      'cmn-Hant',
      'cht',
      'CHT',
    ]) {
      test('recognizes traditional language $language below generic', () {
        final traditional = _track('t', language: language, codec: 'ass');
        final generic = _track('g', language: 'zh');
        expect(preferredChineseSubtitle([traditional]), same(traditional));
        expect(preferredChineseSubtitle([traditional, generic]), same(generic));
      });
    }

    for (final language in ['zh', 'chi', 'zho', 'cmn', ' ZHO ', 'zh-XX']) {
      test('recognizes generic Chinese alias $language', () {
        final generic = _track('g', language: language);
        expect(
          preferredChineseSubtitle([
            _track('t', language: 'zh-TW', codec: 'ssa'),
            generic,
          ]),
          same(generic),
        );
      });
    }

    for (final title in [
      '简体',
      '简中',
      '簡體',
      '簡中',
      '简日双语',
      '简英双语',
      '簡日',
      '簡英',
      '[CHS]',
      'chs / JPN',
      'GB',
      'gb2312',
      'GB18030',
      'Simplified Chinese',
      'chinese-simplified',
    ]) {
      test('recognizes simplified title $title including bilingual', () {
        final simplified = _track('s', title: title);
        expect(
          preferredChineseSubtitle([
            _track('g', language: 'chi', codec: 'ass'),
            simplified,
          ]),
          same(simplified),
        );
      });
    }

    for (final title in [
      '繁体',
      '繁中',
      '繁體',
      '繁日双语',
      '繁英双语',
      '[CHT]',
      'cht / ENG',
      'BIG5',
      'big5',
      'Traditional Chinese',
      'Chinese-Traditional',
    ]) {
      test('recognizes traditional title $title', () {
        final traditional = _track('t', title: title, codec: 'ass');
        final generic = _track('g', language: 'chi');
        expect(preferredChineseSubtitle([traditional]), same(traditional));
        expect(preferredChineseSubtitle([traditional, generic]), same(generic));
      });
    }

    for (final title in ['Chinese', 'CHINESE', '中文字幕', '中日双语', '中英双语']) {
      for (final language in [null, '', ' ', 'und', 'UNKNOWN', 'zxx']) {
        test('generic title $title with absent language $language', () {
          final generic = _track('g', title: title, language: language);
          expect(
            preferredChineseSubtitle([
              _track('t', language: 'zh-Hant', codec: 'ass'),
              generic,
            ]),
            same(generic),
          );
        });
      }
    }

    test('does not mistake English token substrings for Chinese markers', () {
      for (final title in [
        'yachts',
        'CHStuff',
        'xCHS',
        'CHSx',
        'CHTML',
        'xCHT',
        'RGB',
        'GBextra',
        'BIG50',
        'xBIG5',
        'Chineseish',
      ]) {
        expect(
          preferredChineseSubtitle([_track('1', title: title)]),
          isNull,
          reason: title,
        );
      }
    });

    test(
      'explicit non-Chinese language rejects generic descriptive titles',
      () {
        for (final language in ['eng', 'en', 'jpn', 'fr', 'made-up']) {
          for (final title in ['中文字幕组 英文', 'Chinese commentary', '中日', '中英']) {
            expect(
              preferredChineseSubtitle([
                _track('1', language: language, title: title),
              ]),
              isNull,
              reason: '$language / $title',
            );
          }
        }
      },
    );

    test('strong script title identifies mislabeled bilingual subtitles', () {
      for (final title in ['简日双语', '[CHS] English', '繁英双语', '[CHT]']) {
        final bilingual = _track('1', language: 'eng', title: title);
        expect(preferredChineseSubtitle([bilingual]), same(bilingual));
      }
    });

    test('titles refine generic chi without changing script-specific tags', () {
      final generic = _track('g', language: 'zh');
      final refinedSimplified = _track('s', language: 'chi', title: 'CHS');
      final refinedTraditional = _track('t', language: 'zho', title: 'CHT');
      expect(
        preferredChineseSubtitle([generic, refinedSimplified]),
        same(refinedSimplified),
      );
      expect(
        preferredChineseSubtitle([refinedTraditional, generic]),
        same(generic),
      );
      for (final language in ['zh-Hant', 'zh-TW', 'cht']) {
        final conflicting = _track('t', language: language, title: '简体 CHS');
        expect(preferredChineseSubtitle([conflicting, generic]), same(generic));
      }
      for (final language in ['zh-Hans', 'zh-CN', 'chs']) {
        final conflicting = _track('s', language: language, title: '繁體 CHT');
        expect(
          preferredChineseSubtitle([generic, conflicting]),
          same(conflicting),
        );
      }
    });

    test('script outranks conflicting region and generic title', () {
      final traditional = _track('t', language: 'zh-Hant-CN', title: '中文');
      final generic = _track('g', language: 'zh');
      final simplified = _track('s', language: 'zh-Hans-TW', title: 'Chinese');
      expect(preferredChineseSubtitle([traditional, generic]), same(generic));
      expect(preferredChineseSubtitle([generic, simplified]), same(simplified));
    });

    test('a title advertising both scripts includes simplified', () {
      final both = _track('b', title: '繁體 / 简体 [CHT / CHS]');
      expect(
        preferredChineseSubtitle([_track('g', language: 'zh'), both]),
        same(both),
      );
    });

    for (final language in ['zh-Hans', 'zh', 'zh-Hant']) {
      for (final codec in ['ass', 'ssa', 'ASS', ' SsA ']) {
        test('$codec wins within $language but ASS and SSA are equal', () {
          final styled = _track('a', language: language, codec: codec);
          final otherStyled = _track('b', language: language, codec: 'ass');
          expect(
            preferredChineseSubtitle([
              _track('plain', language: language, codec: 'subrip'),
              styled,
              otherStyled,
            ]),
            same(styled),
          );
        });
      }
    }

    test('bitmap is eligible and language tier outranks styled codec', () {
      final bitmap = _track(
        's',
        language: 'zh-CN',
        codec: 'hdmv_pgs_subtitle',
        image: true,
      );
      expect(
        preferredChineseSubtitle([
          _track('t', language: 'zh-TW', codec: 'ass'),
          _track('g', language: 'zh', codec: 'ssa'),
          bitmap,
        ]),
        same(bitmap),
      );
    });

    test('all non-ASS codecs tie stably including bitmap and unknown', () {
      for (final codec in [
        null,
        'unknown',
        'subrip',
        'webvtt',
        'dvd_subtitle',
      ]) {
        final first = _track('first', language: 'chi', codec: codec);
        final bitmap = _track('bitmap', language: 'zho', image: true);
        final tracks = List<SubtitleTrack>.unmodifiable([first, bitmap]);
        expect(preferredChineseSubtitle(tracks), same(first));
        expect(preferredChineseSubtitle(tracks.reversed), same(bitmap));
        expect(tracks, [same(first), same(bitmap)]);
      }
    });

    test('consumes an arbitrary single-pass iterable once', () {
      final best = _track('best', language: 'zh-Hans', codec: 'ass');
      var iterations = 0;
      Iterable<SubtitleTrack> tracks() sync* {
        iterations++;
        if (iterations > 1) throw StateError('iterated twice');
        yield _track('generic', language: 'chi');
        yield best;
        yield _track('traditional', language: 'zh-Hant');
      }

      expect(preferredChineseSubtitle(tracks()), same(best));
      expect(iterations, 1);
    });
  });
}
