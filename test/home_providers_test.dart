import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/features/home/home_providers.dart';

MediaItem episode(
  String id, {
  String? series = 'series',
  String? season,
  int? seasonNumber = 1,
  int? number,
}) => MediaItem(
  id: id,
  name: id,
  type: MediaType.episode,
  seriesId: series,
  seasonId: season,
  parentIndexNumber: seasonNumber,
  indexNumber: number,
);

void main() {
  test('keeps the most recently watched episode, even when rewatching', () {
    final recent = episode('recent', number: 2);
    final older = episode('older', number: 20);
    expect(groupResumeItems([recent, older]), [recent]);
  });

  test('preserves different series, seasons, movies and their ordering', () {
    final recent = episode('recent', season: 'season-1');
    final movie = const MediaItem(
      id: 'movie',
      name: 'Movie',
      type: MediaType.movie,
    );
    final otherSeason = episode('season-2', seasonNumber: 2);
    final otherSeries = episode('other-series', series: 'other');
    final special = episode('special', seasonNumber: 0);
    final items = [recent, movie, otherSeason, otherSeries, special];
    expect(
      groupResumeItems([...items, episode('older', season: 'season-1')]),
      items,
    );
  });

  test('falls back to season ID when series or season number is missing', () {
    final recent = episode(
      'recent',
      series: null,
      season: 'season-1',
      seasonNumber: null,
    );
    final older = episode(
      'older',
      series: null,
      season: 'season-1',
      seasonNumber: null,
    );
    final other = episode(
      'other',
      series: null,
      season: 'season-2',
      seasonNumber: null,
    );
    expect(groupResumeItems([recent, older, other]), [recent, other]);
  });

  test('retains episodes with incomplete season metadata', () {
    final items = [
      episode('unknown-1', seasonNumber: null),
      episode('unknown-2', seasonNumber: null),
      episode('empty-ids', series: '', season: '', seasonNumber: null),
    ];
    expect(groupResumeItems(items), items);
    expect(groupResumeItems([]), isEmpty);
  });
}
