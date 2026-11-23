import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/media_server/server_profile.dart';
import '../../data/media_server/server_repository.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/server_brand.dart';

import '../../shared/widgets.dart';
import 'library_providers.dart';

/// Marks library content whose server action is already rendered by the shell.
class LibraryServerHeaderScope extends InheritedWidget {
  const LibraryServerHeaderScope({
    super.key,
    required this.hasServerAction,
    required super.child,
  });

  final bool hasServerAction;

  static bool hasAction(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<LibraryServerHeaderScope>()
          ?.hasServerAction ??
      false;

  @override
  bool updateShouldNotify(LibraryServerHeaderScope oldWidget) =>
      hasServerAction != oldWidget.hasServerAction;
}

class LibraryServerAction extends ConsumerStatefulWidget {
  const LibraryServerAction({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<LibraryServerAction> createState() =>
      _LibraryServerActionState();
}

class _LibraryServerActionState extends ConsumerState<LibraryServerAction> {
  bool _pickerOpen = false;
  bool _switching = false;

  Future<void> _pick(List<ServerProfile> servers, String currentId) async {
    if (_pickerOpen || _switching) return;
    FocusScope.of(context).unfocus();
    _pickerOpen = true;
    final String? id;
    try {
      id = await _showLibraryServerPicker(
        context,
        servers: servers,
        currentId: currentId,
      );
    } finally {
      _pickerOpen = false;
    }
    if (!mounted || id == null || id == ref.read(activeServerProvider)?.id) {
      return;
    }
    setState(() => _switching = true);
    try {
      await ref.read(serversProvider.notifier).setActive(id);
      if (!mounted || ref.read(activeServerProvider)?.id != id) return;
      final router = GoRouter.maybeOf(context);
      // Item IDs belong to the old server, even if the new server reuses them.
      if (router != null && router.state.fullPath == '/library/:itemId') {
        router.go('/library');
      }
    } catch (error) {
      if (mounted) notifyUser(context, failureMessage(context, error));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider).value ?? const <ServerProfile>[];
    final current = servers.firstOrNull;
    return _LibraryServerButton(
      server: current,
      switching: _switching,
      compact: widget.compact,
      onPress: current == null ? null : () => _pick(servers, current.id),
    );
  }
}

class _LibraryServerButton extends StatelessWidget {
  const _LibraryServerButton({
    required this.compact,
    required this.server,
    required this.switching,
    required this.onPress,
  });

  final bool compact;
  final ServerProfile? server;
  final bool switching;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final name = server?.name ?? context.l10n.noServers;
    final label = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis);
    final size = compact ? 16.0 : 20.0;
    final type = server?.type;
    final icon = type == null
        ? Icon(FLucideIcons.server, size: size)
        : ServerTypeIcon(type: type, size: size);
    return FButton(
      key: const ValueKey('library-server-switch'),
      variant: compact ? .ghost : .outline,
      size: compact ? .xs : .sm,
      mainAxisSize: MainAxisSize.min,
      semanticsLabel: '${context.l10n.librarySwitchServer}: $name',
      onPress: switching ? null : onPress,
      prefix: icon,
      suffix: switching
          ? const SizedBox.square(
              dimension: 16,
              child: FCircularProgress.loader(),
            )
          : null,
      builder: responsiveButtonContent,
      child: label,
    );
  }
}

Future<String?> _showLibraryServerPicker(
  BuildContext context, {
  required List<ServerProfile> servers,
  required String currentId,
}) => showFDialog<String>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  builder: (context, style, animation) => FDialog(
    key: const ValueKey('library-server-switch-dialog'),
    animation: animation,
    semanticsLabel: context.l10n.librarySwitchServer,
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
    builder: (context, style) {
      final l = context.l10n;
      final theme = context.theme;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.librarySwitchServer,
                style: theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final server in servers)
              FButton(
                key: ValueKey('library-server-option-${server.id}'),
                variant: server.id == currentId ? .secondary : .outline,
                selected: server.id == currentId,
                size: .lg,
                mainAxisAlignment: MainAxisAlignment.start,
                onPress: () => Navigator.of(context).pop(server.id),
                prefix: ServerTypeIcon(type: server.type, size: 24),
                suffix: server.id == currentId
                    ? Icon(FLucideIcons.check, color: theme.colors.primary)
                    : null,
                builder: responsiveButtonContent,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          serverTypeLabel(context, server.type),
                          style: theme.typography.body.sm.copyWith(
                            color: theme.colors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FButton(
                key: const ValueKey('library-server-switch-cancel'),
                variant: .ghost,
                mainAxisSize: MainAxisSize.min,
                builder: responsiveButtonContent,
                onPress: () => Navigator.of(context).pop(),
                child: Text(l.cancel),
              ),
            ),
          ],
        ),
      );
    },
  ),
);
