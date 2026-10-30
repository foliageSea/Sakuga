import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../core/settings/settings.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';

Future<void> showPlayerShortcutDialog(BuildContext context) =>
    showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => const _PlayerShortcutSettings(),
      ),
    );

class _PlayerShortcutSettings extends ConsumerStatefulWidget {
  const _PlayerShortcutSettings();

  @override
  ConsumerState<_PlayerShortcutSettings> createState() =>
      _PlayerShortcutSettingsState();
}

class _PlayerShortcutSettingsState
    extends ConsumerState<_PlayerShortcutSettings> {
  late final TextEditingController _backward;
  late final TextEditingController _forward;
  bool _backwardInvalid = false;
  bool _forwardInvalid = false;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _backward = TextEditingController(text: '${settings.seekBackwardSeconds}');
    _forward = TextEditingController(text: '${settings.seekForwardSeconds}');
  }

  @override
  void dispose() {
    _backward.dispose();
    _forward.dispose();
    super.dispose();
  }

  int? _seconds(String input) {
    final text = input.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value != null && value >= 1 && value <= 600 ? value : null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final backward = _seconds(_backward.text);
    final forward = _seconds(_forward.text);
    setState(() {
      _backwardInvalid = backward == null;
      _forwardInvalid = forward == null;
      _error = null;
    });
    if (backward == null || forward == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              seekBackwardSeconds: backward,
              seekForwardSeconds: forward,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
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
          Text(l.playbackShortcuts, style: context.theme.typography.body.lg),
          const SizedBox(height: 20),
          FTextField(
            key: const ValueKey('seek-backward-seconds'),
            control: .managed(controller: _backward),
            label: Text(l.seekBackwardSeconds),
            keyboardType: TextInputType.number,
            enabled: !_saving,
            error: _backwardInvalid ? Text(l.seekSecondsInvalid) : null,
          ),
          const SizedBox(height: 16),
          FTextField(
            key: const ValueKey('seek-forward-seconds'),
            control: .managed(controller: _forward),
            label: Text(l.seekForwardSeconds),
            keyboardType: TextInputType.number,
            enabled: !_saving,
            error: _forwardInvalid ? Text(l.seekSecondsInvalid) : null,
          ),
          const SizedBox(height: 16),
          Text(
            defaultTargetPlatform == TargetPlatform.android
                ? l.saveScreenshotShortcut
                : l.screenshotShortcut,
            style: context.theme.typography.body.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorNotice(_error!),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              FButton(
                key: const ValueKey('player-shortcuts-cancel'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                variant: .outline,
                onPress: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(l.cancel),
              ),
              FButton(
                key: const ValueKey('player-shortcuts-save'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                onPress: _saving ? null : _save,
                child: Text(l.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
