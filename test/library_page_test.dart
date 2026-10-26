import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:sakuga/app/theme.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/data/jellyfin/jellyfin_client.dart';
import 'package:sakuga/data/jellyfin/jellyfin_models.dart';
import 'package:sakuga/data/jellyfin/server_profile.dart';
import 'package:sakuga/data/jellyfin/server_repository.dart';
import 'package:sakuga/features/library/library_page.dart';
import 'package:sakuga/features/library/library_providers.dart';
import 'package:sakuga/l10n/generated/app_localizations.dart';

import 'fakes.dart';

const _server = ServerProfile(
  id: 'server',
  name: 'Test server',
  baseUrl: 'http://127.0.0.1:8096',
  apiKey: 'test-key',
);

JellyfinItem _item(String id, double ratio) => JellyfinItem(
  id: id,
  name: 'Series $id',
  type: 'Series',
  imageTags: const {},
  primaryImageAspectRatio: ratio,
);

class _FakeItems extends LibraryItemsController {
  _FakeItems(super.query);

  @override
  Future<LibraryItemsState> build() async {
    final items = [
      _item('a', 0.5),
      _item('b', 1.2),
      _item('c', 0.7),
      _item('d', 0.7),
    ];
    return LibraryItemsState(items: items, totalRecordCount: items.length);
  }
}

Future<void> _pumpLibrary(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final servers = MemoryServerRepository()..items = [_server];
  final container = ProviderContainer(
    overrides: [
      serverRepositoryProvider.overrideWithValue(servers),
      libraryViewsProvider.overrideWith(
        (ref) async => LibraryData(
          client: JellyfinClient(server: _server),
          userId: 'user-1',
          views: const [
            JellyfinView(id: 'view', name: 'Shows', collectionType: 'tvshows'),
          ],
        ),
      ),
      libraryItemsProvider.overrideWith2(_FakeItems.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...FLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => FTheme(
          data: createAppTheme(
            const AppSettings(language: 'en'),
            brightness: Brightness.light,
            touch: true,
          ),
          child: child!,
        ),
        home: const LibraryPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mobile library flows posters into two staggered columns', (
    tester,
  ) async {
    await _pumpLibrary(tester, const Size(390, 900));

    expect(
      find.byKey(const ValueKey('library-mobile-masonry')),
      findsOneWidget,
    );
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('library-mobile-card-a')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('library-mobile-card-b')),
    );
    final third = tester.getTopLeft(
      find.byKey(const ValueKey('library-mobile-card-c')),
    );

    expect(second.dx, greaterThan(first.dx));
    expect(second.dy, first.dy);
    expect(third.dx, second.dx);
    expect(third.dy, greaterThan(second.dy));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('library-mobile-card-a')))
          .height,
      greaterThan(
        tester
            .getSize(find.byKey(const ValueKey('library-mobile-card-b')))
            .height,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop library keeps the aligned grid', (tester) async {
    await _pumpLibrary(tester, const Size(1280, 900));

    expect(find.byKey(const ValueKey('library-mobile-masonry')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
