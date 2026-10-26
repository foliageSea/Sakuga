import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/logging/file_log_store.dart';
import 'package:sakuga/core/logging/log_archive_service.dart';
import 'package:sakuga/core/logging/log_export_service.dart';
import 'package:sakuga/core/logging/runtime_environment_report.dart';
import 'package:sakuga/core/runtime_environment.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory temporary;
  late FileLogStore store;
  late DateTime now;
  late LogArchiveService archives;
  const report = RuntimeEnvironmentReport(
    environment: RuntimeEnvironment(
      operatingSystem: 'linux',
      operatingSystemVersion: 'Test OS 系统 1.0',
      dartVersion: '3.13.0',
      buildMode: RuntimeBuildMode.release,
      numberOfProcessors: 8,
      systemLocale: 'en_US.UTF-8',
    ),
    appVersion: '1.2.3',
    buildNumber: '42',
    windowSize: Size(1200, 900),
    devicePixelRatio: 2,
    appLocale: 'zh',
  );

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Forui',
      packageName: 'sakuga',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    temporary = await Directory.systemTemp.createTemp('forui-file-logs-test-');
    now = DateTime(2026, 10, 12, 12);
    store = FileLogStore(
      directory: Directory('${temporary.path}/logs'),
      clock: () => now,
    );
    archives = LogArchiveService(
      store: store,
      temporaryDirectory: () async => temporary,
      clock: () => now,
    );
  });

  tearDown(() async {
    await store.flush();
    await temporary.delete(recursive: true);
  });

  Future<File> seed(String name, String contents) async {
    await store.directory.create(recursive: true);
    return File('${store.directory.path}/$name').writeAsString(contents);
  }

  Future<List<FileSystemEntity>> sessions() async =>
      Directory('${temporary.path}/forui-log-exports').list().toList();

  test('writes are serialized, flushed and appended after restart', () async {
    await Future.wait([
      for (var i = 0; i < 40; i++) store.write('record $i', time: now),
    ]);
    await store.flush();
    final file = File('${store.directory.path}/app-2026-10-12.log');
    expect(await file.readAsLines(), [
      for (var i = 0; i < 40; i++) 'record $i',
    ]);
    final restarted = FileLogStore(
      directory: store.directory,
      clock: () => now,
    );
    await restarted.initialize();
    await restarted.write('after restart', time: now);
    expect((await file.readAsLines()).last, 'after restart');
  });

  test(
    'startup retains seven calendar days and leaves unrelated files alone',
    () async {
      final old = await seed('app-2026-10-05.log', 'expired');
      final boundary = await seed('app-2026-10-06.log', 'keep');
      final other = await seed('notes.log', 'not ours');
      final malformed = await seed('app-2026-02-30.log', 'invalid date');
      final folder = await Directory(
        '${store.directory.path}/app-2026-10-01.log',
      ).create();
      await store.initialize();
      expect(await old.exists(), isFalse);
      expect(await boundary.exists(), isTrue);
      expect(await other.exists(), isTrue);
      expect(await malformed.exists(), isTrue);
      expect(await folder.exists(), isTrue);
    },
  );

  test('midnight rotates and clears expired logs without restarting', () async {
    now = DateTime(2026, 10, 12, 23, 59);
    final boundary = await seed('app-2026-10-06.log', 'last retained day');
    await store.write('before midnight', time: now);
    expect(await boundary.exists(), isTrue);
    now = DateTime(2026, 10, 13);
    await store.write('after midnight', time: now);
    expect(await boundary.exists(), isFalse);
    expect(
      await File('${store.directory.path}/app-2026-10-12.log').readAsString(),
      'before midnight\n',
    );
    expect(
      await File('${store.directory.path}/app-2026-10-13.log').readAsString(),
      'after midnight\n',
    );
  });

  test('retention works across month and year boundaries', () async {
    now = DateTime(2027, 1, 3);
    final expired = await seed('app-2026-12-27.log', 'expired');
    final retained = await seed('app-2026-12-28.log', 'keep');
    await store.initialize();
    expect(await expired.exists(), isFalse);
    expect(await retained.exists(), isTrue);
  });

  test('failed writes do not poison subsequent writes', () async {
    final blocker = await File(store.directory.path).writeAsString('blocked');
    await expectLater(store.initialize(), throwsA(isA<FileSystemException>()));
    await expectLater(
      store.write('failed', time: now),
      throwsA(isA<FileSystemException>()),
    );
    await blocker.delete();
    await store.write('recovered', time: now);
    expect(
      await File('${store.directory.path}/app-2026-10-12.log').readAsString(),
      'recovered\n',
    );
  });

  test(
    'snapshots are stable and exclude empty, future and unrelated files',
    () async {
      await seed('app-2026-10-05.log', 'expired');
      await seed('app-2026-10-06.log', 'first retained');
      await seed('app-2026-10-07.log', '');
      await seed('app-2026-10-13.log', 'future');
      await seed('credentials.txt', 'never export');
      final write = store.write('before snapshot', time: now);
      final snapshots = await store.snapshot(
        Directory('${temporary.path}/snapshot'),
      );
      await write;
      expect(snapshots.map((file) => file.uri.pathSegments.last), [
        'app-2026-10-06.log',
        'app-2026-10-12.log',
      ]);
      await store.write('after snapshot', time: now);
      expect(await snapshots.last.readAsString(), 'before snapshot\n');
    },
  );

  test('retention and snapshot do not follow symbolic links', () async {
    await store.initialize();
    final external = await File('${temporary.path}/external.log')
        .writeAsString('private');
    final link = await Link('${store.directory.path}/app-2026-10-01.log')
        .create(external.path);
    now = DateTime(2026, 10, 13);
    await store.write('own data', time: now);
    final snapshot = await store.snapshot(
      Directory('${temporary.path}/snapshot'),
    );
    expect(await link.exists(), isTrue);
    expect(await external.readAsString(), 'private');
    expect(snapshot, hasLength(1));
  }, skip: Platform.isWindows);

  test('ZIP contains retained logs and a UTF-8 environment report', () async {
    await seed('app-2026-10-06.log', 'previous day\n');
    await seed('app-2026-10-05.log', 'expired');
    await seed('unrelated.txt', 'private');
    final writes = [
      for (var i = 0; i < 20; i++) store.write('日志 $i', time: now),
    ];
    final zip = await archives.createArchive(environmentReport: report);
    await Future.wait(writes);
    expect(zip, isNotNull);
    final decoded = ZipDecoder().decodeBytes(await zip!.readAsBytes());
    expect(decoded.files.map((file) => file.name), [
      'app-2026-10-06.log',
      'app-2026-10-12.log',
      'runtime-environment.txt',
    ]);
    expect(utf8.decode(decoded.files.first.content), 'previous day\n');
    expect(
      utf8.decode(decoded.files[1].content),
      [for (var i = 0; i < 20; i++) '日志 $i\n'].join(),
    );
    expect(
      utf8.decode(decoded.files.last.content),
      report.toText(exportedAt: now),
    );
    expect(
      await File('${store.directory.path}/runtime-environment.txt').exists(),
      isFalse,
    );
    expect(await Directory('${zip.parent.path}/snapshot').exists(), isFalse);
  });

  test('writes do not follow a current-day symbolic link', () async {
    await store.initialize();
    final external = await File('${temporary.path}/external.log')
        .writeAsString('private');
    await Link('${store.directory.path}/app-2026-10-12.log')
        .create(external.path);
    await expectLater(
      store.write('must not escape', time: now),
      throwsA(isA<FileSystemException>()),
    );
    expect(await external.readAsString(), 'private');
  }, skip: Platform.isWindows);

  test('export filenames use device-local time without a UTC suffix', () async {
    now = DateTime.utc(2026, 10, 12, 2, 42, 51, 835, 108);
    await store.write('local export', time: now);
    final zip = await archives.createArchive();
    final localStamp = now.toLocal().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    expect(zip!.uri.pathSegments.last, 'forui-logs-$localStamp.zip');
    expect(zip.uri.pathSegments.last, isNot(endsWith('Z.zip')));
    final decoded = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final environment = utf8.decode(decoded.files.last.content);
    expect(decoded.files.last.name, 'runtime-environment.txt');
    expect(environment, contains('Exported at: ${now.toIso8601String()}'));
    expect(environment, contains('App version: 1.0.0'));
    expect(
      environment,
      contains('Operating system: ${Platform.operatingSystem}'),
    );
  });

  test('empty exports do not leave temporary sessions', () async {
    expect(await archives.createArchive(environmentReport: report), isNull);
    expect(await sessions(), isEmpty);
  });

  test(
    'expired export cleanup only removes owned temporary directories',
    () async {
      final root = await Directory('${temporary.path}/forui-log-exports')
          .create();
      final expired = await Directory('${root.path}/export-old').create();
      await File('${expired.path}/logs.zip').writeAsString('old zip');
      final unrelated = await Directory('${root.path}/keep-me').create();
      final futureClock = DateTime.now().add(const Duration(days: 2));
      final cleaner = LogArchiveService(
        store: store,
        temporaryDirectory: () async => temporary,
        clock: () => futureClock,
      );
      await cleaner.cleanupExpiredExports();
      expect(await expired.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    },
  );

  test(
    'failed snapshots leave no incomplete archives and can be retried',
    () async {
      final blocker = await File(store.directory.path).writeAsString('blocked');
      await expectLater(
        archives.createArchive(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sessions(), isEmpty);
      await blocker.delete();
      await store.write('retry', time: now);
      expect(await archives.createArchive(), isNotNull);
    },
  );

  test('retention must be positive', () {
    expect(
      () => FileLogStore(directory: store.directory, retentionDays: 0),
      throwsArgumentError,
    );
  });

  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    test(
      '$platform exports a saved ZIP and cleans its temporary source',
      () async {
        await store.write('saved log', time: now);
        final destination = File('${temporary.path}/saved.zip');
        final service = NativeLogExportService(
          archives: archives,
          platform: platform,
          chooseSaveLocation: (name) async {
            expect(name, startsWith('forui-logs-'));
            expect(name, endsWith('.zip'));
            return destination.path;
          },
          share: (_) async => throw StateError('Desktop must not share'),
        );
        expect(
          await service.export(environmentReport: report),
          LogExportResult.saved,
        );
        final decoded = ZipDecoder().decodeBytes(
          await destination.readAsBytes(),
        );
        expect(decoded.files.map((file) => file.name), [
          'app-2026-10-12.log',
          'runtime-environment.txt',
        ]);
        expect(
          utf8.decode(decoded.files.last.content),
          report.toText(exportedAt: now),
        );
        expect(await sessions(), isEmpty);
      },
    );
  }

  test('save cancellation and failure leave original logs intact', () async {
    await store.write('keep original', time: now);
    final cancelled = NativeLogExportService(
      archives: archives,
      platform: TargetPlatform.linux,
      chooseSaveLocation: (_) async => null,
    );
    expect(await cancelled.export(), LogExportResult.cancelled);
    expect(await sessions(), isEmpty);
    final failed = NativeLogExportService(
      archives: archives,
      platform: TargetPlatform.linux,
      chooseSaveLocation: (_) async =>
          '${temporary.path}/missing-folder/logs.zip',
    );
    await expectLater(failed.export(), throwsA(isA<FileSystemException>()));
    expect(await sessions(), isEmpty);
    expect(
      await File('${store.directory.path}/app-2026-10-12.log').readAsString(),
      'keep original\n',
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform shares a ZIP with an anchor and preserves it for the recipient',
      () async {
        await store.write('shared log', time: now);
        const anchor = Rect.fromLTWH(10, 20, 100, 40);
        late String sharedPath;
        final service = NativeLogExportService(
          archives: archives,
          platform: platform,
          chooseSaveLocation: (_) async =>
              throw StateError('Mobile must not save'),
          share: (params) async {
            expect(params.sharePositionOrigin, anchor);
            expect(params.files, hasLength(1));
            expect(params.files!.single.mimeType, 'application/zip');
            sharedPath = params.files!.single.path;
            expect(await File(sharedPath).exists(), isTrue);
            final decoded = ZipDecoder().decodeBytes(
              await File(sharedPath).readAsBytes(),
            );
            expect(decoded.files.map((file) => file.name), [
              'app-2026-10-12.log',
              'runtime-environment.txt',
            ]);
            expect(
              utf8.decode(decoded.files.last.content),
              report.toText(exportedAt: now),
            );
            return const ShareResult('target', ShareResultStatus.success);
          },
        );
        expect(
          await service.export(
            sharePositionOrigin: anchor,
            environmentReport: report,
          ),
          LogExportResult.shared,
        );
        expect(await File(sharedPath).exists(), isTrue);
      },
    );
  }

  test(
    'mobile cancellation and unavailable results are not reported as saved',
    () async {
      await store.write('shared log', time: now);
      for (final (status, result) in [
        (ShareResultStatus.dismissed, LogExportResult.cancelled),
        (ShareResultStatus.unavailable, LogExportResult.presented),
      ]) {
        final service = NativeLogExportService(
          archives: archives,
          platform: TargetPlatform.iOS,
          share: (_) async => ShareResult('', status),
        );
        expect(await service.export(), result);
      }
    },
  );

  test('empty exports do not open native dialogs', () async {
    final service = NativeLogExportService(
      archives: archives,
      chooseSaveLocation: (_) async => throw StateError('No dialog expected'),
      share: (_) async => throw StateError('No share expected'),
    );
    expect(await service.export(), LogExportResult.empty);
  });

  test(
    'unavailable file logging reports a storage failure to the exporter',
    () async {
      await expectLater(
        NativeLogExportService(archives: null).export(),
        throwsA(
          isA<AppException>().having(
            (error) => error.kind,
            'kind',
            FailureKind.storage,
          ),
        ),
      );
    },
  );
}
