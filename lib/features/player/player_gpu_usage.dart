import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../core/platform/gpu_usage.dart';
import '../../shared/localization.dart';

/// Displays real-time system GPU utilization as a persistent HUD badge when
/// supported by the host platform.
class PlayerGpuUsage extends StatefulWidget {
  const PlayerGpuUsage({
    this.readPercentage = GpuUsage.readPercentage,
    this.pollInterval = const Duration(seconds: 2),
    super.key,
  });

  final Future<int?> Function() readPercentage;
  final Duration pollInterval;

  @override
  State<PlayerGpuUsage> createState() => _PlayerGpuUsageState();
}

class _PlayerGpuUsageState extends State<PlayerGpuUsage>
    with WidgetsBindingObserver {
  Timer? _timer;
  int? _usage;
  bool _reading = false;
  bool _appActive = true;
  bool _tickerEnabled = true;

  bool get _shouldPoll => _appActive && _tickerEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_timer == null && _shouldPoll && enabled) {
      _tickerEnabled = enabled;
      _syncPolling();
      return;
    }
    if (enabled != _tickerEnabled) {
      _tickerEnabled = enabled;
      _syncPolling();
    }
  }

  @override
  void didUpdateWidget(PlayerGpuUsage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pollInterval != widget.pollInterval ||
        oldWidget.readPercentage != widget.readPercentage) {
      _syncPolling(restart: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active != _appActive) {
      _appActive = active;
      _syncPolling();
    }
  }

  void _syncPolling({bool restart = false}) {
    if (!_shouldPoll) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null && !restart) return;
    _timer?.cancel();
    unawaited(_poll());
    _timer = Timer.periodic(widget.pollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (_reading || !_shouldPoll) return;
    _reading = true;
    int? next;
    try {
      next = await widget.readPercentage();
    } finally {
      _reading = false;
    }
    if (mounted && next != _usage) {
      setState(() => _usage = next);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    if (usage == null) return const SizedBox.shrink();
    final label = context.l10n.gpuSystemUsage;
    return Semantics(
      label: '$label $usage%',
      excludeSemantics: true,
      child: DecoratedBox(
        key: const ValueKey('player-gpu-usage'),
        decoration: BoxDecoration(
          color: const Color(0x80000000),
          border: Border.all(color: const Color(0x26FFFFFF)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'GPU $usage%',
            style: context.theme.typography.body.xs.copyWith(
              color: const Color(0xFFFFFFFF),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
