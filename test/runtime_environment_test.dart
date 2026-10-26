import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/runtime_environment.dart';

void main() {
  test(
    'runtime environment reads the current platform, not build-time values',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final environment = container.read(runtimeEnvironmentProvider);

      expect(environment.operatingSystem, Platform.operatingSystem);
      expect(
        environment.operatingSystemVersion,
        Platform.operatingSystemVersion,
      );
      expect(environment.dartVersion, Platform.version);
      expect(environment.numberOfProcessors, Platform.numberOfProcessors);
      expect(environment.systemLocale, Platform.localeName);
      expect(
        environment.buildMode,
        kReleaseMode
            ? RuntimeBuildMode.release
            : kProfileMode
            ? RuntimeBuildMode.profile
            : RuntimeBuildMode.debug,
      );
    },
  );
}
