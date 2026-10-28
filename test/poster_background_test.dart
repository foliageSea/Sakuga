import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:sakuga/shared/poster_background.dart';

PosterBackground _poster(String name) => PosterBackground(
  url: 'https://poster-background.test/$name.jpg',
  headers: const {},
);

Future<void> _show(
  WidgetTester tester,
  PosterBackground? background, {
  bool disableAnimations = false,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: FTheme(
        data: FTheme.neutral.light.touch,
        child: PosterWindowBackground(background: background),
      ),
    ),
  ),
);

Finder _outgoing(PosterBackground background) =>
    find.byKey(ValueKey(('outgoing', background.url)));

double _opacity(WidgetTester tester, PosterBackground background) => tester
    .widget<FadeTransition>(
      find.ancestor(
        of: find.byKey(ValueKey(background.url)),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

VoidCallback _readyCallback(WidgetTester tester, PosterBackground background) {
  final image = find.descendant(
    of: find.byKey(ValueKey(background.url)),
    matching: find.byType(CachedNetworkImage),
  );
  final widget = tester.widget<CachedNetworkImage>(image);
  final context = tester.element(image);
  expect(widget.fadeInDuration, const Duration(milliseconds: 200));
  // Calling the real builder signals its first frame without loading an image.
  // The returned Image is deliberately not mounted.
  return () => widget.imageBuilder!(context, const AssetImage('unused'));
}

// Keep actual requests pending: Flutter's default HTTP 400 would otherwise mark
// artwork settled through errorWidget before the controlled ready callback.
class _PendingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _PendingHttpClient();
}

class _PendingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _PendingHttpRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _PendingHttpRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _PendingHttpHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() => Completer<HttpClientResponse>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _PendingHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _PendingHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
  });

  testWidgets(
    'ready just before outer completion retains outgoing for inner fade',
    (tester) async {
      final a = _poster('before-a');
      final b = _poster('before-b');
      await _show(tester, a);
      _readyCallback(tester, a)();
      await _show(tester, b);
      await tester.pump(const Duration(milliseconds: 256));
      expect(_opacity(tester, b), allOf(greaterThan(0), lessThan(1)));
      final ready = _readyCallback(tester, b);
      ready();

      await tester.pump(const Duration(milliseconds: 45));
      expect(_opacity(tester, b), 1);
      // B's inner fade has run for only 45ms when the outer fade completes.
      expect(_outgoing(a), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      ready(); // Rebuilding an already ready image must not extend the timer.
      await _show(tester, b);
      await tester.pump(const Duration(milliseconds: 119));
      expect(_outgoing(a), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_outgoing(a), findsNothing);
      expect(find.byKey(ValueKey(b.url)), findsOneWidget);
    },
  );

  testWidgets(
    'ready after outer completion starts a full protection interval',
    (tester) async {
      final a = _poster('after-a');
      final b = _poster('after-b');
      await _show(tester, a);
      await _show(tester, b);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_opacity(tester, b), 1);
      expect(_outgoing(a), findsOneWidget);

      final ready = _readyCallback(tester, b);
      ready();
      await tester.pump(const Duration(milliseconds: 100));
      ready();
      await tester.pump(const Duration(milliseconds: 119));
      expect(_outgoing(a), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(_outgoing(a), findsNothing);
    },
  );

  testWidgets('A to B to C cancels B release and ignores stale B readiness', (
    tester,
  ) async {
    final a = _poster('rapid-a');
    final b = _poster('rapid-b');
    final c = _poster('rapid-c');
    await _show(tester, a);
    await _show(tester, b);
    await tester.pump(const Duration(milliseconds: 256));
    final readyB = _readyCallback(tester, b);
    readyB();
    await tester.pump(const Duration(milliseconds: 45));
    await tester.pump(const Duration(milliseconds: 100));
    await _show(tester, c);
    expect(_outgoing(a), findsNothing);
    expect(_outgoing(b), findsOneWidget);

    readyB();
    // This crosses the old t=520 release deadline while C is still fading.
    await tester.pump(const Duration(milliseconds: 120));
    expect(_opacity(tester, c), allOf(greaterThan(0), lessThan(1)));
    expect(_outgoing(b), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 181));
    expect(_opacity(tester, c), 1);
    expect(_outgoing(b), findsOneWidget);
    _readyCallback(tester, c)();
    await tester.pump(const Duration(milliseconds: 219));
    expect(_outgoing(b), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(_outgoing(b), findsNothing);
  });

  testWidgets(
    'clearing during protection cancels release and finishes fade out',
    (tester) async {
      final a = _poster('clear-a');
      final b = _poster('clear-b');
      await _show(tester, a);
      await _show(tester, b);
      _readyCallback(tester, b)();
      await tester.pump(const Duration(milliseconds: 301));
      await tester.pump(const Duration(milliseconds: 100));
      await _show(tester, null);
      expect(_outgoing(a), findsNothing);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_opacity(tester, b), allOf(greaterThan(0), lessThan(1)));
      await tester.pump(const Duration(milliseconds: 141));
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disableAnimations switches and clears without outgoing or delay',
    (tester) async {
      final a = _poster('disabled-a');
      final b = _poster('disabled-b');
      await _show(tester, a, disableAnimations: true);
      await _show(tester, b, disableAnimations: true);
      expect(_outgoing(a), findsNothing);
      expect(_opacity(tester, b), 1);
      _readyCallback(tester, b)();
      await _show(tester, null, disableAnimations: true);
      expect(find.byType(CachedNetworkImage), findsNothing);
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing during protection cancels the pending release', (
    tester,
  ) async {
    final a = _poster('dispose-a');
    final b = _poster('dispose-b');
    await _show(tester, a);
    await _show(tester, b);
    _readyCallback(tester, b)();
    await tester.pump(const Duration(milliseconds: 301));
    expect(_outgoing(a), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.takeException(), isNull);
  });
}
