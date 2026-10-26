import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/features/player/player_exit.dart';

void main() {
  test('return navigates before slow storage or network completes', () async {
    final local = Completer<void>();
    final server = Completer<void>();
    final events = <String>[];
    leavePlayer(
      localSave: local.future,
      serverSync: server.future,
      refresh: () => events.add('refresh'),
      navigate: () => events.add('navigate'),
    );
    expect(events, ['navigate']);

    local.complete();
    await Future<void>.value();
    expect(events, ['navigate', 'refresh']);
    expect(server.isCompleted, isFalse);

    server.complete();
    await Future<void>.value();
    expect(events, ['navigate', 'refresh', 'refresh']);
  });
}
