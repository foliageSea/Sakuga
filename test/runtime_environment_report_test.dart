import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/logging/runtime_environment_report.dart';
import 'package:sakuga/core/runtime_environment.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  const environment = RuntimeEnvironment(
    operatingSystem: 'linux',
    operatingSystemVersion: 'Test 系统 1.0',
    dartVersion: '3.13.0 (stable)',
    buildMode: RuntimeBuildMode.profile,
    numberOfProcessors: 8,
    systemLocale: 'en_US.UTF-8',
  );

  test('report includes all runtime fields and a UTC export timestamp', () {
    const report = RuntimeEnvironmentReport(
      environment: environment,
      appVersion: '1.2.3',
      buildNumber: '42',
      windowSize: Size(1200, 900),
      devicePixelRatio: 2,
      appLocale: 'zh-CN',
    );
    final exportedAt = DateTime(2026, 10, 13, 12);
    expect(
      report.toText(exportedAt: exportedAt),
      [
        'Exported at: ${exportedAt.toUtc().toIso8601String()}',
        'App version: 1.2.3',
        'Build number: 42',
        'Operating system: linux',
        'System version: Test 系统 1.0',
        'Dart version: 3.13.0 (stable)',
        'Build mode: profile',
        'Processor count: 8',
        'Window size: 1200 × 900 logical px',
        'Device pixel ratio: 2.00',
        'System locale: en_US.UTF-8',
        'App locale: zh-CN',
        '',
      ].join('\n'),
    );
  });

  test(
    'collection preserves the supplied environment and view snapshot',
    () async {
      final report = await RuntimeEnvironmentReport.collect(
        environment: environment,
        windowSize: const Size(390, 1000),
        devicePixelRatio: 3,
        appLocale: 'en',
        packageInfo: () async => PackageInfo(
          appName: 'Forui',
          packageName: 'forui_app',
          version: '2.0.0',
          buildNumber: '5',
        ),
      );
      expect(report.environment, same(environment));
      expect(report.appVersion, '2.0.0');
      expect(report.buildNumber, '5');
      expect(report.windowSize, const Size(390, 1000));
      expect(report.devicePixelRatio, 3);
      expect(report.appLocale, 'en');
    },
  );

  test(
    'missing package metadata does not prevent generating a report',
    () async {
      final report = await RuntimeEnvironmentReport.collect(
        environment: environment,
        packageInfo: () async =>
            throw StateError('Package metadata unavailable'),
      );
      final text = report.toText(exportedAt: DateTime.utc(2026, 10, 13));
      expect(text, contains('Operating system: linux'));
      expect(text, contains('App version: Unavailable'));
      expect(text, contains('Build number: Unavailable'));
      expect(text, contains('Window size: Unavailable'));
      expect(text, contains('Device pixel ratio: Unavailable'));
      expect(text, contains('App locale: Unavailable'));
    },
  );
}
