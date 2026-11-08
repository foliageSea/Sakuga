import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/features/player/player_errors.dart';

void main() {
  test('native playback logs omit authenticated URLs and raw credentials', () {
    final message = redactPlaybackError(
      'Failed https://media.test/stream?api_key=private-token X-Emby-Token: private-token',
      secrets: ['private-token'],
    );
    expect(message, isNot(contains('private-token')));
    expect(message, isNot(contains('https://')));
    expect(message, contains('Failed'));
  });

  const subtitle =
      'http://media.test/Videos/item/source/Subtitles/2/0/Stream.dvdsub?api_key=test';
  const video = 'http://media.test/Videos/item/stream.mkv?api_key=test';

  test('external subtitle open errors do not indicate video failure', () {
    for (final message in [
      'Failed to open $subtitle.',
      'Can not open external file $subtitle.',
      'Failed to open $subtitle',
    ]) {
      expect(isExternalSubtitleLoadError(message, [subtitle]), isTrue);
    }
  });

  test('video open and decoding failures remain fatal', () {
    for (final message in [
      'Failed to open $video.',
      'Failed to open $subtitle.other.',
      'Error decoding video frame',
      'Cannot load file or stream',
    ]) {
      expect(isExternalSubtitleLoadError(message, [subtitle]), isFalse);
    }
  });

  test('unknown resources and missing subtitle URLs remain fatal', () {
    expect(
      isExternalSubtitleLoadError('Failed to open $subtitle.', []),
      isFalse,
    );
    expect(
      isExternalSubtitleLoadError('Failed to open $video.', ['']),
      isFalse,
    );
    expect(
      isExternalSubtitleLoadError('Failed to open $subtitle.other.', [
        subtitle,
      ]),
      isFalse,
    );
  });
}
