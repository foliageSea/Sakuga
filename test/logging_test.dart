import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/logging.dart';
import 'package:sakuga/core/logging/file_log_store.dart';
import 'package:sakuga/core/logging/live_log_store.dart';
import 'package:logging/logging.dart';
import 'package:stack_trace/stack_trace.dart';

class FirstService with LoggingMixin {}

class SecondService with LoggingMixin {}

void main() {
  setUp(() {
    final level = Logger.root.level;
    addTearDown(() => Logger.root.level = level);
    Logger.root.level = Level.ALL;
  });

  test('mixin names loggers by class and reuses same-class loggers', () {
    final first = FirstService();
    final second = SecondService();
    expect(first.log.name, 'FirstService');
    expect(second.log.name, 'SecondService');
    expect(identical(first.log, FirstService().log), isTrue);
    expect(identical(first.log, second.log), isFalse);
  });

  test('named loggers forward errors and stack traces to the root', () {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    final error = StateError('Storage failed');
    final stack = StackTrace.current;

    FirstService().log.severe('Settings write failed', error, stack);

    final record = records.single;
    expect(record.loggerName, 'FirstService');
    expect(record.level, Level.SEVERE);
    expect(record.message, 'Settings write failed');
    expect(record.error, same(error));
    expect(record.stackTrace, same(stack));
  });

  test(
    'initialization outputs details once and filters verbose logs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'forui-logging-test-',
      );
      final store = FileLogStore(
        directory: Directory('${directory.path}/logs'),
      );
      addTearDown(() async {
        await store.flush();
        await directory.delete(recursive: true);
      });
      final output = <String?>[];
      final originalDebugPrint = debugPrint;
      addTearDown(() => debugPrint = originalDebugPrint);
      debugPrint = (String? message, {int? wrapWidth}) => output.add(message);

      await initializeLogging(
        fileStore: store,
        temporaryDirectory: () async => directory,
      );
      await initializeLogging();
      expect(Logger.root.level, Level.FINE);

      final service = FirstService();
      service.log.finest('Hidden');
      expect(output, isEmpty);
      expect(applicationLogs.snapshot, isEmpty);
      final loadingLine = Trace.current().frames.first.line! + 1;
      service.log.fine('Loading');
      expect(applicationLogs.snapshot.single.text, contains('Loading'));
      expect(output.single, contains('FINE:'));
      expect(
        output.single,
        contains('[FirstService] [logging_test.dart:$loadingLine] Loading'),
      );
      output.clear();

      final error = StateError('Storage failed');
      final stack = StackTrace.fromString('test stack trace');
      final errorLine = Trace.current().frames.first.line! + 1;
      service.log.severe('Write failed', error, stack);
      expect(output.single, contains('SEVERE:'));
      expect(
        output.single,
        contains('[FirstService] [logging_test.dart:$errorLine] Write failed'),
      );
      expect(output.single, contains(error.toString()));
      expect(output.single, contains(stack.toString()));
      expect(applicationLogs.snapshot.last.text, output.single);
      output.clear();

      final mainLog = Logger('main');
      final mainLine = Trace.current().frames.first.line! + 1;
      mainLog.warning('Bootstrap warning');
      expect(
        output.single,
        contains('[main] [logging_test.dart:$mainLine] Bootstrap warning'),
      );
      await store.flush();
      final files = await store.directory
          .list()
          .where((file) => file is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      final contents = await files.single.readAsString();
      expect(
        contents,
        contains('[FirstService] [logging_test.dart:$loadingLine] Loading'),
      );
      expect(
        contents,
        contains('[FirstService] [logging_test.dart:$errorLine] Write failed'),
      );
      expect(contents, contains(error.toString()));
      expect(contents, contains(stack.toString()));
      expect(
        contents,
        contains('[main] [logging_test.dart:$mainLine] Bootstrap warning'),
      );
      expect(contents, isNot(contains('Hidden')));
    },
  );
}
