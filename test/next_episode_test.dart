import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/features/detail/detail_providers.dart';

MediaItem _ep(
  int n, {
  int season = 1,
  bool played = false,
  Duration? position,
  DateTime? lastPlayedAt,
}) => MediaItem(
  id: 's$season-e$n',
  name: 'Episode $n',
  type: MediaType.episode,
  indexNumber: n,
  parentIndexNumber: season,
  played: played,
  playbackPosition: position,
  lastPlayedAt: lastPlayedAt,
);

void main() {
  test('empty list has no next episode', () {
    expect(resolveNextEpisode(const []), isNull);
  });

  test('unwatched list starts at the first regular episode', () {
    final next = resolveNextEpisode([_ep(1, season: 0), _ep(1), _ep(2)]);
    expect(next?.episode.id, 's1-e1');
    expect(next?.resume, isFalse);
  });

  test('continues after the last watched episode', () {
    final next = resolveNextEpisode([
      _ep(1, played: true),
      _ep(2),
      _ep(3, played: true),
      _ep(4),
    ]);
    expect(next?.episode.id, 's1-e4');
  });

  test('fully watched list restarts from the first episode', () {
    final next = resolveNextEpisode([
      _ep(1, played: true),
      _ep(2, played: true),
    ]);
    expect(next?.episode.id, 's1-e1');
  });

  test('the most recently resumed episode wins', () {
    final next = resolveNextEpisode([
      _ep(
        1,
        position: const Duration(minutes: 1),
        lastPlayedAt: DateTime(2026, 1, 2),
      ),
      _ep(2, played: true),
      _ep(
        3,
        position: const Duration(minutes: 5),
        lastPlayedAt: DateTime(2026, 1, 1),
      ),
    ]);
    expect(next?.episode.id, 's1-e1');
    expect(next?.resume, isTrue);
  });

  test('specials are used when a list has only specials', () {
    expect(resolveNextEpisode([_ep(1, season: 0)])?.episode.id, 's0-e1');
  });
}
