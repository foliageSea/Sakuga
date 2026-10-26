import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/logging.dart';
import 'package:sakuga/core/logging/file_log_store.dart';
import 'package:sakuga/core/logging/live_log_store.dart';
import 'package:logging/logging.dart';

void main() {
  test(
    'failed file initialization preserves console output and can recover',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'forui-log-fallback-test-',
      );
      final store = FileLogStore(
        directory: Directory('${temporary.path}/logs'),
      );
      final blocker = await File(store.directory.path).writeAsString('blocked');
      final output = <String?>[];
      final originalDebugPrint = debugPrint;
      final originalLevel = Logger.root.level;
      addTearDown(() async {
        await store.flush();
        debugPrint = originalDebugPrint;
        Logger.root.level = originalLevel;
        await temporary.delete(recursive: true);
      });
      debugPrint = (String? message, {int? wrapWidth}) => output.add(message);

      final initialization = initializeLogging(
        fileStore: store,
        temporaryDirectory: () async => temporary,
      );
      expect(identical(initialization, initializeLogging()), isTrue);
      final log = Logger('FallbackTest');
      log.warning('Warning during initialization');
      await initialization;
      await store.flush();
      expect(
        applicationLogs.snapshot.single.text,
        contains('Warning during initialization'),
      );
      expect(
        output.where((line) => line!.contains('Warning during initialization')),
        hasLength(1),
      );
      expect(
        output.where(
          (line) => line!.contains('File logging initialization failed'),
        ),
        hasLength(1),
      );
      expect(
        output.where((line) => line!.contains('File log write failed')),
        hasLength(1),
      );

      await blocker.delete();
      output.clear();
      log.warning('Storage recovered');
      await store.flush();
      expect(output, hasLength(1));
      expect(output.single, contains('[FallbackTest]'));
      final files = await store.directory
          .list()
          .where((file) => file is File)
          .cast<File>()
          .toList();
      expect(await files.single.readAsString(), contains('Storage recovered'));
    },
  );
}
