import 'dart:ui';

import 'package:sakuga/core/app_exception.dart';
import 'package:sakuga/core/logging/log_export_service.dart';
import 'package:sakuga/core/logging/runtime_environment_report.dart';
import 'package:sakuga/core/settings/settings.dart';
import 'package:sakuga/core/window/desktop_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/media_server_client.dart';
import 'package:sakuga/data/media_server/media_models.dart';
import 'package:sakuga/data/media_server/server_profile.dart';
import 'package:sakuga/data/media_server/server_repository.dart';

class FakeMediaServerClient extends Fake implements MediaServerClient {
  FakeMediaServerClient({required this.server});
  @override
  final ServerProfile server;

  @override
  bool get isConfigured => true;

  @override
  Future<List<MediaUser>> users() async => const [
    MediaUser(id: 'user-1', name: 'User'),
  ];

  @override
  Future<List<MediaLibrary>> views(String userId) async => const [];
}

class FakeLogExporter implements LogExportService {
  LogExportResult result = LogExportResult.empty;
  Object? error;
  Future<LogExportResult>? pending;
  int exports = 0;
  Rect? lastOrigin;
  RuntimeEnvironmentReport? lastEnvironmentReport;

  @override
  Future<LogExportResult> export({
    Rect? sharePositionOrigin,
    RuntimeEnvironmentReport? environmentReport,
  }) async {
    exports++;
    lastOrigin = sharePositionOrigin;
    lastEnvironmentReport = environmentReport;
    if (error != null) throw error!;
    return pending ?? result;
  }
}

class MemorySettings implements SettingsRepository {
  AppSettings value = const AppSettings(language: 'en');
  bool fail = false;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    if (fail) throw const AppException(FailureKind.storage);
    value = settings;
  }
}

class MemoryServerRepository implements ServerRepository {
  List<ServerProfile> items = [];
  bool fail = false;

  @override
  Future<List<ServerProfile>> load() async => List.of(items);

  @override
  Future<void> save(List<ServerProfile> servers) async {
    if (fail) throw const AppException(FailureKind.storage);
    items = List.of(servers);
  }
}

class FakeWindow extends DesktopWindowController {
  FakeWindow({this.available = false, this.macOS = false});
  @override
  final bool available;
  @override
  final bool macOS;
  @override
  bool maximized = false;
  @override
  bool fullScreen = false;
  @override
  bool focused = true;
  int drags = 0, minimizes = 0, closes = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> drag() async {
    drags++;
  }

  @override
  Future<void> minimize() async {
    minimizes++;
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<void> toggleMaximize() async {
    maximized = !maximized;
    notifyListeners();
  }
}
