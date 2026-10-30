import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../core/platform/window_brightness.dart';
import '../../shared/localization.dart';
import '../../shared/widgets.dart';
import 'player_controls_controller.dart';

enum _Adjustment { seek, brightness, volume }

class PlayerGestureSurface extends StatefulWidget {
  const PlayerGestureSurface({
    required this.controller,
    required this.onTap,
    required this.onToggleFullscreen,
    required this.onInteractionChanged,
    this.enabled = true,
    super.key,
  });

  final PlayerControlsController controller;
  final VoidCallback onTap;
  final Future<void> Function() onToggleFullscreen;
  final ValueChanged<bool> onInteractionChanged;
  final bool enabled;

  @override
  State<PlayerGestureSurface> createState() => _PlayerGestureSurfaceState();
}

class _PlayerGestureSurfaceState extends State<PlayerGestureSurface>
    with WidgetsBindingObserver {
  _Adjustment? _adjustment;
  Duration _startPosition = Duration.zero;
  Duration _targetPosition = Duration.zero;
  double _startValue = 0;
  double _value = 0;
  double _distance = 0;
  bool _touchDoubleTap = false;
  int _generation = 0;
  Timer? _hudTimer;
  bool _showHud = false;
  bool _changedBrightness = false;
  bool _brightnessReady = false;
  Future<void> _writes = Future.value();

  PlayerControlsController? _boostController;
  double? _originalRate;
  Future<void> _rateWrites = Future.value();

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  void _writeRate(PlayerControlsController controller, double rate) {
    // Always restore after an in-flight boost write, even after disposal.
    _rateWrites = _rateWrites.then((_) async {
      try {
        await controller.setRate(rate);
      } catch (_) {
        if (mounted) notifyUser(context, context.l10n.playerAdjustmentError);
      }
    });
  }

  void _boostStart(LongPressStartDetails details) {
    if (!widget.enabled ||
        !widget.controller.playing ||
        _originalRate != null) {
      return;
    }
    _hudTimer?.cancel();
    _boostController = widget.controller;
    _originalRate = widget.controller.rate;
    setState(() {
      _adjustment = null;
      _showHud = true;
    });
    widget.onInteractionChanged(true);
    _writeRate(_boostController!, 2);
  }

  void _restoreRate() {
    final controller = _boostController;
    final rate = _originalRate;
    _boostController = null;
    _originalRate = null;
    if (controller != null && rate != null) _writeRate(controller, rate);
  }

  void _boostEnd() {
    if (_originalRate == null) return;
    _restoreRate();
    setState(() => _showHud = false);
    widget.onInteractionChanged(false);
  }

  @override
  void didUpdateWidget(PlayerGestureSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.enabled && oldWidget.enabled) ||
        widget.controller != oldWidget.controller) {
      _cancel();
    }
  }

  void _begin(_Adjustment adjustment) {
    _generation++;
    _hudTimer?.cancel();
    _distance = 0;
    _startPosition = widget.controller.position;
    _targetPosition = _startPosition;
    setState(() {
      _adjustment = adjustment;
      _showHud = true;
    });
    widget.onInteractionChanged(true);
  }

  void _seekStart(DragStartDetails details) {
    if (!widget.enabled || widget.controller.duration <= Duration.zero) return;
    _begin(_Adjustment.seek);
  }

  void _seekUpdate(DragUpdateDetails details) {
    if (_adjustment != _Adjustment.seek || !widget.enabled) return;
    _distance += details.delta.dx;
    final width = context.size!.width;
    // A full-width swipe covers three minutes, independent of media length.
    final offset = (_distance / width * 180000).round();
    setState(() {
      _targetPosition = Duration(
        milliseconds: (_startPosition.inMilliseconds + offset).clamp(
          0,
          widget.controller.duration.inMilliseconds,
        ),
      );
    });
  }

  Future<void> _seekEnd(DragEndDetails details) async {
    if (_adjustment != _Adjustment.seek || !widget.enabled) return;
    final generation = _generation;
    try {
      await widget.controller.seek(_targetPosition);
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.playerAdjustmentError);
    } finally {
      if (mounted && generation == _generation) _finish();
    }
  }

  Future<void> _verticalStart(DragStartDetails details) async {
    if (!widget.enabled) return;
    final brightness = details.localPosition.dx < context.size!.width / 2;
    _brightnessReady = false;
    _begin(brightness ? _Adjustment.brightness : _Adjustment.volume);
    _startValue = brightness ? 0.5 : widget.controller.volume / 100;
    _value = _startValue;
    if (!brightness) return;
    final generation = _generation;
    try {
      await _writes;
      final value = await WindowBrightness.read();
      if (!mounted || generation != _generation) return;
      _startValue = value;
      _brightnessReady = true;
      _updateValue();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _cancel();
      notifyUser(context, context.l10n.playerAdjustmentError);
    }
  }

  void _verticalUpdate(DragUpdateDetails details) {
    if (!widget.enabled ||
        (_adjustment != _Adjustment.brightness &&
            _adjustment != _Adjustment.volume)) {
      return;
    }
    _distance += details.delta.dy;
    if (_adjustment == _Adjustment.brightness && !_brightnessReady) return;
    _updateValue();
  }

  void _updateValue() {
    setState(() {
      _value = (_startValue - _distance / (context.size!.height * 0.75)).clamp(
        0,
        1,
      );
    });
    final adjustment = _adjustment;
    final value = _value;
    final generation = _generation;
    // Serialize native writes, dropping superseded updates in the same gesture.
    _writes = _writes.then((_) async {
      if (!mounted || generation != _generation || value != _value) return;
      try {
        if (adjustment == _Adjustment.brightness) {
          _changedBrightness = true;
          await WindowBrightness.set(value);
        } else {
          await widget.controller.setVolume(value * 100);
        }
      } catch (_) {
        if (mounted && generation == _generation) {
          _cancel();
          notifyUser(context, context.l10n.playerAdjustmentError);
        }
      }
    });
  }

  void _finish() {
    widget.onInteractionChanged(false);
    _hudTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHud = false);
    });
  }

  void _cancel() {
    _restoreRate();
    _generation++;
    _hudTimer?.cancel();
    setState(() {
      _adjustment = null;
      _showHud = false;
    });
    widget.onInteractionChanged(false);
  }

  Future<void> _doubleTap() async {
    if (!widget.enabled) return;
    try {
      if (_touchDoubleTap) {
        await widget.controller.playOrPause();
      } else {
        await widget.onToggleFullscreen();
      }
    } catch (_) {
      if (mounted) notifyUser(context, context.l10n.playerAdjustmentError);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreRate();
    _generation++;
    _hudTimer?.cancel();
    // Await any in-flight write so the restore is always the final operation.
    unawaited(
      _writes.then((_) async {
        if (_changedBrightness) {
          try {
            await WindowBrightness.reset();
          } catch (_) {
            // The Android window may already have been destroyed.
          }
        }
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerCancel: (_) => _cancel(),
    child: GestureDetector(
      key: const ValueKey('player-control-surface'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: (details) {
        _touchDoubleTap =
            _android &&
            (details.kind == PointerDeviceKind.touch ||
                details.kind == PointerDeviceKind.stylus);
      },
      onDoubleTap: _doubleTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
        onLongPressStart: _android ? _boostStart : null,
        onLongPressEnd: _android ? (_) => _boostEnd() : null,
        onLongPressCancel: _android ? _boostEnd : null,
        onHorizontalDragStart: _android ? _seekStart : null,
        onHorizontalDragUpdate: _android ? _seekUpdate : null,
        onHorizontalDragEnd: _android ? _seekEnd : null,
        onHorizontalDragCancel: _android ? _cancel : null,
        onVerticalDragStart: _android ? _verticalStart : null,
        onVerticalDragUpdate: _android ? _verticalUpdate : null,
        onVerticalDragEnd: _android ? (_) => _finish() : null,
        onVerticalDragCancel: _android ? _cancel : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_showHud)
              Center(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xCC000000),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            switch (_adjustment) {
                              _Adjustment.brightness => FLucideIcons.sun,
                              _Adjustment.volume => FLucideIcons.volume2,
                              _ => FLucideIcons.fastForward,
                            },
                            size: 20,
                            color: const Color(0xFFFFFFFF),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _hudText(context),
                            key: const ValueKey('player-gesture-hud'),
                            style: context.theme.typography.body.sm.copyWith(
                              color: const Color(0xFFFFFFFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  String _hudText(BuildContext context) {
    if (_originalRate != null) return '2×';
    if (_adjustment == _Adjustment.seek) {
      final delta = (_targetPosition - _startPosition).inSeconds;
      return '${_time(_targetPosition)} / ${_time(widget.controller.duration)}'
          '\n${delta >= 0 ? '+' : ''}${delta}s';
    }
    final label = _adjustment == _Adjustment.brightness
        ? context.l10n.playerBrightness
        : context.l10n.playerVolume;
    return '$label · ${(_value * 100).round()}%';
  }

  String _time(Duration value) {
    final seconds = value.inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
