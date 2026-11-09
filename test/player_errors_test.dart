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

  test('only stopped or prematurely ended files count as aborted', () {
    const duration = Duration(minutes: 10);
    expect(
      isPlaybackAborted(
        idle: true,
        endReached: false,
        position: Duration.zero,
        duration: Duration.zero,
      ),
      isTrue,
    );
    // Still playing: recoverable decoder, audio-output or retry messages.
    expect(
      isPlaybackAborted(
        idle: false,
        endReached: false,
        position: const Duration(seconds: 49),
        duration: duration,
      ),
      isFalse,
    );
    // A dropped stream reaches the end early under keep-open.
    expect(
      isPlaybackAborted(
        idle: false,
        endReached: true,
        position: const Duration(minutes: 3),
        duration: duration,
      ),
      isTrue,
    );
    // A normal end is not a failure.
    expect(
      isPlaybackAborted(
        idle: false,
        endReached: true,
        position: duration - const Duration(seconds: 1),
        duration: duration,
      ),
      isFalse,
    );
  });

  test('error gate reports only after mpv confirms it stopped', () async {
    const delay = Duration(milliseconds: 40);
    Future<void> wait([int factor = 3]) => Future<void>.delayed(delay * factor);
    var stopped = false;
    final fatal = <String>[];
    final gate = PlaybackErrorGate(
      isStopped: () async => stopped,
      onFatal: fatal.add,
      delay: delay,
    );
    gate.report('Could not open/initialize audio device -> no sound.');
    await wait();
    expect(fatal, isEmpty, reason: 'playback continued');

    stopped = true;
    gate.report('first');
    gate.report('tcp: Connection refused');
    await wait();
    expect(fatal, ['tcp: Connection refused'], reason: 'debounced to latest');

    gate.report('superseded');
    gate.reset();
    await wait();
    expect(fatal, hasLength(1), reason: 'new media drops pending checks');

    final failing = PlaybackErrorGate(
      isStopped: () async => throw StateError('disposed'),
      onFatal: fatal.add,
      delay: delay,
    );
    failing.report('unknown');
    await wait();
    expect(fatal.last, 'unknown');
  });
}
