import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:media_kit/media_kit.dart';

import '../../core/settings/settings.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';
import 'player_slider.dart';

/// Authored ASS/SSA styles and bitmap subtitles must be drawn by mpv.
bool usesNativeSubtitleRendering(
  SubtitleTrack selected,
  List<SubtitleTrack> available,
) {
  if (selected.id == 'no' || selected.id == 'auto') return false;
  var track = selected;
  for (final candidate in available) {
    if (candidate.id == selected.id) {
      track = candidate;
      break;
    }
  }
  return track.image == true ||
      const {
        'ass',
        'ssa',
        'dvdsub',
        'dvd_subtitle',
        'pgssub',
        'hdmv_pgs_subtitle',
        'dvbsub',
        'dvb_subtitle',
        'xsub',
      }.contains(track.codec?.toLowerCase());
}

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
              return StreamBuilder<VideoParams>(
                stream: player.stream.videoParams,
                initialData: player.state.videoParams,
                builder: (context, snapshot) {
                  final params = snapshot.data;
                  final width = params?.dw ?? params?.w;
                  final height = params?.dh ?? params?.h;
                  var aspect = params?.aspect;
                  if (aspect == null || !aspect.isFinite || aspect <= 0) {
                    aspect = width != null && height != null && height > 0
                        ? width / height
                        : null;
                  }
                  if ((params?.rotate ?? 0) % 180 != 0 && aspect != null) {
                    aspect = 1 / aspect;
                  }
                  return SubtitlePlacement(
                    position: settings.subtitleVerticalPosition,
                    videoAspectRatio: aspect,
                    child: SubtitleCaption(
                      text: text,
                      fontSize: settings.subtitleFontSize,
                      backgroundOpacity: settings.subtitleBackgroundOpacity,
                      shadowStrength: settings.subtitleShadowStrength,
                      textScaler: TextScaler.linear(scale),
                    ),
                  );
                },
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
    this.videoAspectRatio,
    super.key,
  });

  final double position;
  final Widget child;
  final double? videoAspectRatio;

  @override
  Widget build(BuildContext context) {
    final placement = SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: ClipRect(
        child: Align(
          alignment: Alignment(0, position.clamp(0, 1) * 2 - 1),
          child: child,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = videoAspectRatio;
        if (defaultTargetPlatform != TargetPlatform.android ||
            constraints.maxHeight <= constraints.maxWidth ||
            aspect == null ||
            !aspect.isFinite ||
            aspect <= 0) {
          return placement;
        }
        // In portrait, anchor subtitles to the video instead of the tall
        // letterboxed player viewport. Keep the saved position as a fraction.
        final videoHeight = math.min(
          constraints.maxHeight,
          constraints.maxWidth / aspect,
        );
        return Center(
          child: SizedBox(
            height: videoHeight,
            width: double.infinity,
            child: placement,
          ),
        );
      },
    );
  }
}

class SubtitleCaption extends StatelessWidget {
  const SubtitleCaption({
    required this.text,
    required this.fontSize,
    required this.backgroundOpacity,
    this.shadowStrength = 0.5,
    this.textScaler = TextScaler.noScaling,
    super.key,
  });

  final String text;
  final double fontSize;
  final double backgroundOpacity;

  /// 0 disables the text shadow; 0.5 matches the original look.
  final double shadowStrength;
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
          shadows: shadowStrength <= 0
              ? null
              : [
                  Shadow(
                    blurRadius: 4 * shadowStrength,
                    color: const Color(0xFF000000)
                        .withValues(alpha: 0.2 + 0.8 * shadowStrength),
                  ),
                ],
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
    constraints: const BoxConstraints.tightFor(width: 480),
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
  late double _shadowStrength;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _fontSize = settings.subtitleFontSize;
    _opacity = settings.subtitleBackgroundOpacity;
    _verticalPosition = settings.subtitleVerticalPosition;
    _shadowStrength = settings.subtitleShadowStrength;
  }

  Future<void> _save() async {
    final fontSize = _fontSize;
    final opacity = _opacity;
    final verticalPosition = _verticalPosition;
    final shadowStrength = _shadowStrength;
    try {
      await ref
          .read(settingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              subtitleFontSize: fontSize,
              subtitleBackgroundOpacity: opacity,
              subtitleVerticalPosition: verticalPosition,
              subtitleShadowStrength: shadowStrength,
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
            inactiveColor: context.theme.colors.mutedForeground,
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
            inactiveColor: context.theme.colors.mutedForeground,
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
            inactiveColor: context.theme.colors.mutedForeground,
            key: const ValueKey('subtitle-vertical-position'),
            value: _verticalPosition,
            onChange: (value) => setState(() => _verticalPosition = value),
            onEnd: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text('${l.subtitleShadow} · ${(_shadowStrength * 100).round()}%'),
          const SizedBox(height: 8),
          PlayerSlider(
            inactiveColor: context.theme.colors.mutedForeground,
            key: const ValueKey('subtitle-shadow-strength'),
            value: _shadowStrength,
            onChange: (value) => setState(() => _shadowStrength = value),
            onEnd: (_) => _save(),
          ),
        ],
      ),
    );
  }
}
