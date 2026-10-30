import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/settings/settings.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import 'player_slider.dart';

class PlayerSubtitles extends ConsumerWidget {
  const PlayerSubtitles({required this.player, super.key});

  final Player player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return IgnorePointer(
      child: StreamBuilder<List<String>>(
        stream: player.stream.subtitle,
        initialData: player.state.subtitle,
        builder: (context, snapshot) {
          final text = (snapshot.data ?? const <String>[])
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .join('\n');
          if (text.isEmpty) return const SizedBox.shrink();
          return LayoutBuilder(
            builder: (context, constraints) {
              final scale = math.sqrt(
                (constraints.maxWidth * constraints.maxHeight / (1920 * 1080))
                    .clamp(0.0, 1.0),
              );
              return SubtitlePlacement(
                position: settings.subtitleVerticalPosition,
                child: SubtitleCaption(
                  text: text,
                  fontSize: settings.subtitleFontSize,
                  backgroundOpacity: settings.subtitleBackgroundOpacity,
                  textScaler: TextScaler.linear(scale),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SubtitlePlacement extends StatelessWidget {
  const SubtitlePlacement({
    required this.position,
    required this.child,
    super.key,
  });

  final double position;
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: ClipRect(
      child: Align(
        alignment: Alignment(0, position.clamp(0, 1) * 2 - 1),
        child: child,
      ),
    ),
  );
}

class SubtitleCaption extends StatelessWidget {
  const SubtitleCaption({
    required this.text,
    required this.fontSize,
    required this.backgroundOpacity,
    this.textScaler = TextScaler.noScaling,
    super.key,
  });

  final String text;
  final double fontSize;
  final double backgroundOpacity;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF000000).withValues(alpha: backgroundOpacity),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        text,
        textAlign: TextAlign.center,
        textScaler: textScaler,
        style: TextStyle(
          fontFamily: 'MiSans',
          fontSize: fontSize,
          height: 1.4,
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.normal,
          decoration: TextDecoration.none,
          shadows: const [Shadow(blurRadius: 2, color: Color(0x99000000))],
        ),
      ),
    ),
  );
}

Future<void> showSubtitleStyleDialog(BuildContext context) => showFDialog<void>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  routeStyle: .delta(barrierFilter: () => null),
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, style) => const _SubtitleStyleSettings(),
  ),
);

class _SubtitleStyleSettings extends ConsumerStatefulWidget {
  const _SubtitleStyleSettings();

  @override
  ConsumerState<_SubtitleStyleSettings> createState() =>
      _SubtitleStyleSettingsState();
}

class _SubtitleStyleSettingsState
    extends ConsumerState<_SubtitleStyleSettings> {
  late double _fontSize;
  late double _opacity;
  late double _verticalPosition;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _fontSize = settings.subtitleFontSize;
    _opacity = settings.subtitleBackgroundOpacity;
    _verticalPosition = settings.subtitleVerticalPosition;
  }

  Future<void> _save() async {
    final fontSize = _fontSize;
    final opacity = _opacity;
    final verticalPosition = _verticalPosition;
    try {
      await ref
          .read(settingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              subtitleFontSize: fontSize,
              subtitleBackgroundOpacity: opacity,
              subtitleVerticalPosition: verticalPosition,
            ),
          );
    } catch (error) {
      if (mounted) notifyUser(context, failureMessage(context, error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.subtitleStyle,
            style: context.theme.dialogStyle.titleTextStyle,
          ),
          const SizedBox(height: 20),
          Text('${l.fontSize} · ${_fontSize.round()}'),
          const SizedBox(height: 8),
          PlayerSlider(
            key: const ValueKey('subtitle-font-size'),
            value: (_fontSize - 16) / 48,
            tooltipBuilder: (value) => Text('${(16 + value * 48).round()}'),
            onChange: (value) =>
                setState(() => _fontSize = (16 + value * 48).roundToDouble()),
            onEnd: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text('${l.subtitleBackgroundOpacity} · ${(_opacity * 100).round()}%'),
          const SizedBox(height: 8),
          PlayerSlider(
            key: const ValueKey('subtitle-background-opacity'),
            value: _opacity,
            onChange: (value) => setState(() => _opacity = value),
            onEnd: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text(
            '${l.subtitleVerticalPosition} · ${(_verticalPosition * 100).round()}%',
          ),
          const SizedBox(height: 8),
          PlayerSlider(
            key: const ValueKey('subtitle-vertical-position'),
            value: _verticalPosition,
            onChange: (value) => setState(() => _verticalPosition = value),
            onEnd: (_) => _save(),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FButton(
              builder: responsiveButtonContent,
              mainAxisSize: MainAxisSize.min,
              variant: .outline,
              onPress: () => Navigator.of(context).pop(),
              child: Text(l.close),
            ),
          ),
        ],
      ),
    );
  }
}
