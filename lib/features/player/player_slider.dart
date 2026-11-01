import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class PlayerSlider extends StatelessWidget {
  const PlayerSlider({
    required this.value,
    required this.onChange,
    this.onEnd,
    this.enabled = true,
    this.tooltipBuilder,
    this.inactiveColor,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChange;
  final ValueChanged<double>? onEnd;
  final bool enabled;

  /// Track color for solid panels; defaults to translucent white over video.
  final Color? inactiveColor;
  final Widget Function(double)? tooltipBuilder;

  @override
  Widget build(BuildContext context) {
    final primary = context.theme.colors.primary;
    return FSlider(
      enabled: enabled,
      layout: FLayout.ltr,
      control: .liftedContinuous(
        value: FSliderValue(max: value.clamp(0, 1)),
        onChange: (value) => onChange(value.max),
      ),
      onEnd: (value) => onEnd?.call(value.max),
      trackHitRegionCrossExtent: 24,
      style: .delta(
        crossAxisExtent: 4,
        thumbSize: 12,
        activeColor: FVariants.all(primary),
        inactiveColor: FVariants.all(inactiveColor ?? const Color(0x33FFFFFF)),
        thumbStyle: .delta(
          color: FVariants.all(primary),
          borderColor: FVariants.all(primary),
        ),
      ),
      tooltipBuilder: (controller, value) =>
          tooltipBuilder?.call(value) ?? Text('${(value * 100).round()}%'),
    );
  }
}
