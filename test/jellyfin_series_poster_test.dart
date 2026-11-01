import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/jellyfin/jellyfin_mapper.dart';

void main() {
  test('keeps series poster separate from episode primary artwork', () {
    const mapper = JellyfinMapper(
      baseUrl: 'https://media.test',
      headers: {'Authorization': 'test'},
    );
    final item = mapper.item({
      'Id': 'episode',
      'Name': 'Episode',
      'Type': 'Episode',
      'ImageTags': {'Primary': 'still-tag'},
      'SeriesId': 'series',
      'SeriesPrimaryImageTag': 'poster-tag',
    });
    expect(item.poster!.url(), contains('/Items/episode/Images/Primary?'));
    expect(item.seriesPoster!.url(), contains('/Items/series/Images/Primary?'));
    expect(item.seriesPoster!.url(), contains('tag=poster-tag'));
    expect(item.seriesPoster!.headers, {'Authorization': 'test'});
    expect(
      item.withPlaybackPosition(const Duration(seconds: 10)).seriesPoster,
      same(item.seriesPoster),
    );
  });

  test('missing series artwork retains episode fallback', () {
    const mapper = JellyfinMapper(baseUrl: 'https://media.test', headers: {});
    final item = mapper.item({
      'Id': 'episode',
      'Type': 'Episode',
      'ImageTags': {'Primary': 'still-tag'},
    });
    expect(item.seriesPoster, isNull);
    expect(item.poster, isNotNull);
  });
}
