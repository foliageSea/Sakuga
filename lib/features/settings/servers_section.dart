import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/jellyfin_probe.dart';
import '../../data/jellyfin/server_profile.dart';
import '../../data/jellyfin/server_repository.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';

class ServersSection extends ConsumerStatefulWidget {
  const ServersSection({super.key});

  @override
  ConsumerState<ServersSection> createState() => _ServersSectionState();
}

class _ServersSectionState extends ConsumerState<ServersSection> {
  String? _switchingServerId;
  Object? _switchError;

  Future<void> _switchServer(String id) async {
    if (_switchingServerId != null) return;
    setState(() {
      _switchingServerId = id;
      _switchError = null;
    });
    try {
      await ref.read(serversProvider.notifier).setActive(id);
      if (mounted) context.go('/library');
    } catch (error) {
      if (mounted) setState(() => _switchError = error);
    } finally {
      if (mounted) setState(() => _switchingServerId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final servers = ref.watch(serversProvider);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.servers,
                  style: context.theme.typography.body.lg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FButton.icon(
                key: const ValueKey('add-server'),
                variant: .outline,
                onPress: _switchingServerId != null
                    ? null
                    : () => _showEditor(context, ref),
                semanticsLabel: l.addServer,
                child: const Icon(FLucideIcons.plus),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_switchError != null) ...[
            ErrorNotice(_switchError!),
            const SizedBox(height: 16),
          ],
          servers.when(
            data: (items) => items.isEmpty
                ? EmptyNotice(
                    l.noServers,
                    child: FButton(
                      builder: responsiveButtonContent,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () => _showEditor(context, ref),
                      child: Text(l.addServer),
                    ),
                  )
                : Column(
                    children: [
                      for (final server in items) ...[
                        _ServerTile(
                          key: ValueKey(server.id),
                          server: server,
                          active: server.id == items.first.id,
                          switching: server.id == _switchingServerId,
                          onSwitch: _switchingServerId != null
                              ? null
                              : () => _switchServer(server.id),
                          onEdit: _switchingServerId != null
                              ? null
                              : () => _showEditor(context, ref, server: server),
                          onDelete: _switchingServerId != null
                              ? null
                              : () => _confirmDelete(context, ref, server),
                        ),
                        if (server != items.last) const SizedBox(height: 8),
                      ],
                    ],
                  ),
            loading: () => const LoadingNotice(),
            error: (error, _) => ErrorNotice(
              error,
              onRetry: () => ref.invalidate(serversProvider),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context,
    WidgetRef ref, {
    ServerProfile? server,
  }) async {
    final l = context.l10n;
    final nameController = TextEditingController(text: server?.name ?? '');
    final urlController = TextEditingController(text: server?.baseUrl ?? '');
    final apiKeyController = TextEditingController(text: server?.apiKey ?? '');
    String? error;
    String? probeResult;
    var testing = false;

    await showFDialog<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  server == null ? l.addServer : l.editServer,
                  style: context.theme.typography.body.lg.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                FTextField(
                  key: const ValueKey('server-name'),
                  control: .managed(controller: nameController),
                  label: Text(l.serverName),
                ),
                const SizedBox(height: 12),
                FTextField(
                  key: const ValueKey('server-url'),
                  control: .managed(controller: urlController),
                  label: Text(l.serverUrl),
                  hint: 'http://192.168.1.2:8096',
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                FTextField.password(
                  key: const ValueKey('server-api-key'),
                  control: .managed(controller: apiKeyController),
                  label: Text(l.apiKey),
                ),
                if (probeResult != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${l.connectedServer} · $probeResult',
                    style: context.theme.typography.body.sm.copyWith(
                      color: context.theme.colors.primary,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: context.theme.typography.body.sm.copyWith(
                      color: context.theme.colors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FButton(
                      builder: responsiveButtonContent,
                      mainAxisSize: MainAxisSize.min,
                      variant: .ghost,
                      onPress: () => Navigator.of(context).pop(),
                      child: Text(l.cancel),
                    ),
                    FButton(
                      builder: responsiveButtonContent,
                      mainAxisSize: MainAxisSize.min,
                      variant: .outline,
                      onPress: testing
                          ? null
                          : () async {
                              setState(() {
                                testing = true;
                                error = null;
                                probeResult = null;
                              });
                              try {
                                final result = await ref
                                    .read(jellyfinProbeProvider)
                                    .probe(
                                      urlController.text,
                                      apiKey: apiKeyController.text,
                                    );
                                if (!context.mounted) return;
                                setState(() {
                                  probeResult = result.version.isEmpty
                                      ? result.name
                                      : '${result.name} ${result.version}';
                                });
                              } catch (e) {
                                if (!context.mounted) return;
                                setState(
                                  () => error = failureMessage(context, e),
                                );
                              } finally {
                                if (context.mounted) {
                                  setState(() => testing = false);
                                }
                              }
                            },
                      child: Text(l.testConnection),
                    ),
                    FButton(
                      builder: responsiveButtonContent,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () async {
                        final name = nameController.text.trim();
                        final rawUrl = urlController.text.trim();
                        if (name.isEmpty) {
                          setState(() => error = l.serverNameRequired);
                          return;
                        }
                        String baseUrl;
                        try {
                          baseUrl = normalizeBaseUrl(rawUrl);
                        } on FormatException {
                          setState(() => error = l.serverUrlInvalid);
                          return;
                        }
                        final profile = ServerProfile(
                          id:
                              server?.id ??
                              DateTime.now().microsecondsSinceEpoch.toString(),
                          name: name,
                          baseUrl: baseUrl,
                          apiKey: apiKeyController.text.trim(),
                        );
                        try {
                          if (server == null) {
                            await ref
                                .read(serversProvider.notifier)
                                .add(profile);
                          } else {
                            await ref
                                .read(serversProvider.notifier)
                                .upsert(profile);
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        } catch (e) {
                          if (context.mounted) {
                            setState(() => error = failureMessage(context, e));
                          }
                        }
                      },
                      child: Text(l.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nameController.dispose();
    urlController.dispose();
    apiKeyController.dispose();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ServerProfile server,
  ) async {
    final l = context.l10n;
    final confirmed = await showFDialog<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.deleteServer,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(l.deleteServerBody),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  FButton(
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    variant: .ghost,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(l.cancel),
                  ),
                  FButton(
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    variant: .destructive,
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(l.delete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(serversProvider.notifier).remove(server.id);
    }
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    super.key,
    required this.server,
    required this.active,
    required this.switching,
    required this.onSwitch,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerProfile server;
  final bool active;
  final bool switching;
  final VoidCallback? onSwitch;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: context.theme.colors.border),
      borderRadius: context.theme.style.borderRadius.md,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  server.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.sm.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FTooltip(
            tipBuilder: (context, controller) => Text(
              active ? context.l10n.currentServer : context.l10n.switchServer,
            ),
            child: FButton.icon(
              key: ValueKey('switch-server-${server.id}'),
              variant: .ghost,
              onPress: active ? null : onSwitch,
              semanticsLabel: active
                  ? context.l10n.currentServer
                  : context.l10n.switchServer,
              child: switching
                  ? const FCircularProgress.loader()
                  : Icon(
                      active ? FLucideIcons.check : FLucideIcons.arrowRightLeft,
                    ),
            ),
          ),
          FButton.icon(
            variant: .ghost,
            onPress: onEdit,
            semanticsLabel: context.l10n.edit,
            child: const Icon(FLucideIcons.pencil),
          ),
          FButton.icon(
            variant: .ghost,
            onPress: onDelete,
            semanticsLabel: context.l10n.delete,
            child: const Icon(FLucideIcons.trash2),
          ),
        ],
      ),
    ),
  );
}
