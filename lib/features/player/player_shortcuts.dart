import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/settings/settings.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';

Future<void> showPlayerShortcutDialog(BuildContext context) =>
    showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        constraints: const BoxConstraints.tightFor(width: 400),
        animation: animation,
        builder: (context, style) => const _PlayerShortcutSettings(),
      ),
    );

const _minSeconds = 1;
const _maxSeconds = 600;

class _PlayerShortcutSettings extends ConsumerStatefulWidget {
  const _PlayerShortcutSettings();

  @override
  ConsumerState<_PlayerShortcutSettings> createState() =>
      _PlayerShortcutSettingsState();
}

class _PlayerShortcutSettingsState
    extends ConsumerState<_PlayerShortcutSettings> {
  Object? _error;

  Future<void> _step({required bool forward, required int delta}) async {
    int adjust(int value) => (value + delta).clamp(_minSeconds, _maxSeconds);
    try {
      await ref
          .read(settingsProvider.notifier)
          .update(
            (settings) => forward
                ? settings.copyWith(
                    seekForwardSeconds: adjust(settings.seekForwardSeconds),
                  )
                : settings.copyWith(
                    seekBackwardSeconds: adjust(settings.seekBackwardSeconds),
                  ),
          );
      if (mounted && _error != null) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final l = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.playbackShortcuts,
            style: context.theme.dialogStyle.titleTextStyle,
          ),
          const SizedBox(height: 20),
          _SeekSecondsStepper(
            key: const ValueKey('seek-backward-seconds'),
            label: l.seekBackwardSeconds,
            value: settings.seekBackwardSeconds,
            onStep: (delta) => _step(forward: false, delta: delta),
          ),
          const SizedBox(height: 16),
          _SeekSecondsStepper(
            key: const ValueKey('seek-forward-seconds'),
            label: l.seekForwardSeconds,
            value: settings.seekForwardSeconds,
            onStep: (delta) => _step(forward: true, delta: delta),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorNotice(_error!),
          ],
        ],
      ),
    );
  }
}

class _SeekSecondsStepper extends StatelessWidget {
  const _SeekSecondsStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onStep,
  });

  final String label;
  final int value;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    const buttonSize = 44.0;
    const labelGap = 16.0;
    const valuePadding = 8.0;
    final theme = context.theme;
    final l = context.l10n;
    final border = BorderSide(color: theme.colors.border);
    final labelStyle = DefaultTextStyle.of(context).style;
    final valueStyle = labelStyle.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    // Reserve room for three digits so the buttons don't move as values change.
    final valueSize = measure(l.seekStepperValue(_maxSeconds), valueStyle);
    final width =
        2 * buttonSize +
        valueSize.width.ceil() +
        2 * (valuePadding + border.width);
    final height = math.max(buttonSize, valueSize.height.ceilToDouble() + 12);
    final control = SizedBox(
      width: width,
      child: Container(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(border),
          borderRadius: theme.style.borderRadius.md,
        ),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: buttonSize,
                child: FButton.icon(
                  variant: .ghost,
                  semanticsLabel: '$label −1',
                  onPress: value > _minSeconds ? () => onStep(-1) : null,
                  child: const Icon(FLucideIcons.minus, size: 16),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(left: border, right: border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: valuePadding,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l.seekStepperValue(value), style: valueStyle),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: buttonSize,
                child: FButton.icon(
                  variant: .ghost,
                  semanticsLabel: '$label +1',
                  onPress: value < _maxSeconds ? () => onStep(1) : null,
                  child: const Icon(FLucideIcons.plus, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(label);
        if (measure(label, labelStyle).width + labelGap + width >
            constraints.maxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [labelText, control],
          );
        }
        return Row(
          spacing: labelGap,
          children: [
            Expanded(child: labelText),
            control,
          ],
        );
      },
    );
  }
}
