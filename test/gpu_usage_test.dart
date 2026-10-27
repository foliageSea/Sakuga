import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/platform/gpu_usage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.foliage.sakuga/gpu_usage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('reads and clamps GPU percentage on macOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = <MethodCall>[];
    var response = 48.6 as num?;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });

    expect(await GpuUsage.readPercentage(), 49);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'read');

    response = -5;
    expect(await GpuUsage.readPercentage(), 0);

    response = 135;
    expect(await GpuUsage.readPercentage(), 100);

    response = null;
    expect(await GpuUsage.readPercentage(), isNull);
  });

  test('skips native channel on non-macOS platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var called = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      called = true;
      return 50;
    });

    expect(await GpuUsage.readPercentage(), isNull);
    expect(called, isFalse);
  });

  test('returns null on platform errors or missing plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    // MissingPluginException when no handler is registered.
    expect(await GpuUsage.readPercentage(), isNull);

    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(await GpuUsage.readPercentage(), isNull);
  });
}
