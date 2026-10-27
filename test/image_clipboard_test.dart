import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/platform/image_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.foliage.sakuga/image_clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  );

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('sends PNG image bytes over the dedicated native channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    await ImageClipboard.writePng(png);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'writePng');
    expect(calls.single.arguments, isA<Uint8List>());
    expect(calls.single.arguments, orderedEquals(png));
  });

  test('propagates native clipboard failures to callers', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'clipboard_write_failed',
        message: 'Denied',
      );
    });

    await expectLater(
      ImageClipboard.writePng(png),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'clipboard_write_failed',
        ),
      ),
    );
  });

  test('propagates an unavailable platform implementation', () async {
    await expectLater(
      ImageClipboard.writePng(png),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('rejects empty and non-PNG data before calling native code', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return null;
    });

    for (final invalid in [
      Uint8List(0),
      Uint8List(8),
      Uint8List.fromList([1, 2]),
    ]) {
      await expectLater(ImageClipboard.writePng(invalid), throwsArgumentError);
    }
    expect(called, isFalse);
  });
}
