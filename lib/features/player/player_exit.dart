import 'dart:async';

/// Leaves immediately while the already captured playback snapshot finishes
/// saving. Refreshes the library once locally durable and once synchronized.
void leavePlayer({
  required Future<void> localSave,
  required Future<void> serverSync,
  required void Function() refresh,
  required void Function() navigate,
}) {
  unawaited(localSave.then((_) => refresh()));
  unawaited(serverSync.then((_) => refresh()));
  navigate();
}
