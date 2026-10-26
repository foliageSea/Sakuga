import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sakuga/app/app.dart';
import 'package:sakuga/app/router.dart';
import 'package:sakuga/core/logging/log_export_service.dart';
import 'package:sakuga/core/runtime_environment.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:sakuga/data/jellyfin/server_repository.dart';
import 'package:sakuga/features/settings/settings_page.dart';

import 'fakes.dart';

class TestViewSize {
  const TestViewSize(this.width, this.height);
  final double width;
  final double height;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

ProviderContainer appContainer({
  FakeWindow? window,
  MemorySettings? settingsRepository,
  LogExportService? logExporter,
  RuntimeEnvironment? environment,
  AppSettings settings = const AppSettings(language: 'en'),
}) => ProviderContainer(
  overrides: [
    if (environment != null)
      runtimeEnvironmentProvider.overrideWithValue(environment),
    initialSettingsProvider.overrideWithValue(settings),
    settingsRepositoryProvider.overrideWithValue(
      settingsRepository ?? MemorySettings(),
    ),
    desktopWindowProvider.overrideWithValue(window ?? FakeWindow()),
    serverRepositoryProvider.overrideWithValue(MemoryServerRepository()),
    logExportServiceProvider.overrideWithValue(
      logExporter ?? FakeLogExporter(),
    ),
    packageInfoProvider.overrideWith(
      (ref) async => PackageInfo(
        appName: 'Sakuga',
        packageName: 'sakuga',
        version: '0.1.0',
        buildNumber: '1',
      ),
    ),
  ],
);

void main() {
  testWidgets('app boots to home and navigates all branches', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    addTearDown(tester.view.resetPhysicalSize);
    final container = appContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);

    for (final path in [
      '/home',
      '/library',
      '/search',
      '/downloads',
      '/settings',
    ]) {
      container.read(routerProvider).go(path);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: path);
    }

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('desktop shell renders five branches', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = appContainer(
      window: FakeWindow(available: true, macOS: true),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SakugaApp()),
    );
    await settle(tester);
    expect(find.text('SAKUGA'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Search'), findsWidgets);
    expect(find.text('Downloads'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
