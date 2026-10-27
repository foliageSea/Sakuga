import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

// Player buttons sit on dark video overlays even when the app uses a light theme.
final playerOverlayButtonStyle = FButtonStyleDelta.delta(
  decoration: .delta([
    .base(
      .shapeDelta(
        color: const Color(0x00000000),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    ),
    .exact({
      .hovered,
      .pressed,
      .selected,
    }, .shapeDelta(color: const Color(0x26FFFFFF))),
    .exact({
      .disabled,
      .selected.and(.disabled),
    }, .shapeDelta(color: const Color(0x00000000))),
  ]),
);
