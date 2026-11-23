import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/window/desktop_window.dart';
import '../../shared/widgets.dart';

/// Gives the title and blank space in the player header desktop window actions.
/// The surrounding controls and the video keep their own gestures.
class PlayerWindowDragRegion extends ConsumerWidget {
  const PlayerWindowDragRegion({
    required this.fullscreen,
    required this.child,
    super.key,
  });

  final bool fullscreen;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(desktopWindowProvider);
    if (!window.available || fullscreen) return child;

    Future<void> perform(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (context.mounted) {
          notifyUser(context, failureMessage(context, error));
        }
      }
    }

    return ListenableBuilder(
      listenable: window,
      child: child,
      builder: (context, child) => window.fullScreen
          ? child!
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              supportedDevices: const {PointerDeviceKind.mouse},
              onPanStart: (_) => perform(window.drag),
              onDoubleTap: () => perform(window.toggleMaximize),
              child: child,
            ),
    );
  }
}
