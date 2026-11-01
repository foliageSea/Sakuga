import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Sends the mouse back button through the router's normal back handling.
class MouseBackNavigation extends StatefulWidget {
  const MouseBackNavigation({
    required this.onBack,
    required this.child,
    super.key,
  });

  final Future<bool> Function() onBack;
  final Widget child;

  @override
  State<MouseBackNavigation> createState() => _MouseBackNavigationState();
}

class _MouseBackNavigationState extends State<MouseBackNavigation> {
  bool _handlingBack = false;

  Future<void> _onPointerDown(PointerDownEvent event) async {
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kBackMouseButton) == 0 ||
        _handlingBack) {
      return;
    }
    _handlingBack = true;
    try {
      await widget.onBack();
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _onPointerDown,
    child: widget.child,
  );
}
