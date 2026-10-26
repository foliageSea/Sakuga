import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/app/router.dart';

void main() {
  testWidgets('the player route carries the item to play', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    final match = router.configuration.findMatch(
      Uri.parse('/player?item=episode-1'),
    );

    expect(match.error, isNull);
    // One match: a nested player route would build an empty player page under
    // the page that carries the item.
    expect(match.matches, hasLength(1));
    expect(match.uri.queryParameters['item'], 'episode-1');
  });
}
