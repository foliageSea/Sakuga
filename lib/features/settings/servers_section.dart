import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_exception.dart';
import '../../data/emby/emby_auth.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/server_probe.dart';
import '../../data/media_server/server_profile.dart';
import '../../data/media_server/server_repository.dart';
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
                variant: .ghost,
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
  }) => showFDialog<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      builder: (context, style) => _ServerEditor(server: server),
    ),
  );

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

class _ServerEditor extends ConsumerStatefulWidget {
  const _ServerEditor({this.server});
  final ServerProfile? server;

  @override
  ConsumerState<_ServerEditor> createState() => _ServerEditorState();
}

class _ServerEditorState extends ConsumerState<_ServerEditor> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _apiKey;
  late final TextEditingController _username;
  final _password = TextEditingController();
  late MediaServerType _type;
  late bool _secure;
  bool _busy = false;
  bool _saving = false;
  bool _sessionRejected = false;
  int _revision = 0;
  String? _error;
  String? _result;
  ServerProfile? _authenticated;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _name = TextEditingController(text: server?.name ?? '');
    _url = TextEditingController(
      text: stripBaseUrlScheme(server?.baseUrl ?? ''),
    );
    _apiKey = TextEditingController(text: server?.apiKey ?? '');
    _username = TextEditingController(text: server?.username ?? '');
    _type = server?.type ?? MediaServerType.jellyfin;
    _secure = isSecureBaseUrl(server?.baseUrl ?? '');
    for (final controller in [_name, _url, _apiKey, _username, _password]) {
      controller.addListener(_inputsChanged);
    }
  }

  void _inputsChanged() {
    setState(() {
      _revision++;
      _authenticated = null;
      _result = null;
      _error = null;
    });
  }

  @override
  void dispose() {
    for (final controller in [_name, _url, _apiKey, _username, _password]) {
      controller.removeListener(_inputsChanged);
      controller.dispose();
    }
    super.dispose();
  }

  bool _acceptsResponse(int revision) =>
      mounted &&
      revision == _revision &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _submit({required bool save}) async {
    if (_busy) return;
    final l = context.l10n;
    if (save && _name.text.trim().isEmpty) {
      setState(() => _error = l.serverNameRequired);
      return;
    }
    String baseUrl;
    try {
      baseUrl = composeBaseUrl(_url.text, secure: _secure);
    } on FormatException {
      setState(() => _error = l.serverUrlInvalid);
      return;
    }
    final revision = _revision;
    final old = widget.server;
    final username = _username.text.trim();
    final password = _password.text;
    final emby = _type == MediaServerType.emby;
    final identityChanged =
        old == null ||
        old.type != _type ||
        old.baseUrl != baseUrl ||
        (emby && old.username != username);
    final needsLogin =
        emby &&
        (identityChanged ||
            _sessionRejected ||
            password.isNotEmpty ||
            old.accessToken.isEmpty ||
            old.userId.isEmpty);
    if (needsLogin && username.isEmpty) {
      setState(() => _error = l.serverUsernameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _saving = save;
      _error = null;
      _result = null;
    });
    try {
      var profile = ServerProfile(
        id: identityChanged
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : old.id,
        name: _name.text.trim(),
        baseUrl: baseUrl,
        type: _type,
        apiKey: emby ? '' : _apiKey.text.trim(),
        accessToken: emby && !identityChanged ? old.accessToken : '',
        userId: emby && !identityChanged ? old.userId : '',
        username: emby ? username : '',
        deviceId: emby && !identityChanged ? old.deviceId : '',
        remoteServerId: emby && !identityChanged ? old.remoteServerId : '',
      );
      if (needsLogin) {
        if (_authenticated != null) {
          profile = _authenticated!;
        } else {
          final auth = ref.read(embyAuthProvider);
          final deviceId = await ref.read(embyDeviceIdProvider.future);
          if (!_acceptsResponse(revision)) return;
          final result = await auth.authenticate(
            baseUrl: baseUrl,
            username: username,
            password: password,
            deviceId: deviceId,
          );
          if (!_acceptsResponse(revision)) return;
          // The authenticated user ID is authoritative if a server renamed an account.
          final accountChanged =
              old != null &&
              (old.userId != result.userId ||
                  old.remoteServerId != result.remoteServerId);
          profile = ServerProfile(
            id: accountChanged && !identityChanged
                ? DateTime.now().microsecondsSinceEpoch.toString()
                : profile.id,
            name: profile.name,
            baseUrl: baseUrl,
            type: MediaServerType.emby,
            accessToken: result.accessToken,
            userId: result.userId,
            username: result.username,
            deviceId: deviceId,
            remoteServerId: result.remoteServerId,
          );
          _authenticated = profile;
        }
      } else if (!save && emby) {
        // Public server information does not validate a saved user session.
        await ref
            .read(mediaServerFactoryProvider)
            .createClient(profile)
            .users();
      } else if (!save) {
        final result = await ref
            .read(serverProbeProvider(_type))
            .probe(baseUrl, apiKey: profile.apiKey);
        if (!_acceptsResponse(revision)) return;
        _result = result.version.isEmpty
            ? result.name
            : '${result.name} ${result.version}';
      }
      if (!_acceptsResponse(revision)) return;
      if (save) {
        final notifier = ref.read(serversProvider.notifier);
        if (old == null) {
          await notifier.add(profile);
        } else {
          await notifier.upsert(profile, replacingId: old.id);
        }
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _result ??= profile.username);
      }
    } catch (error) {
      if (_acceptsResponse(revision)) {
        final rejected =
            emby &&
            (error is AppException && error.kind == FailureKind.auth ||
                error is DioException && error.response?.statusCode == 401);
        setState(() {
          if (rejected) {
            _sessionRejected = true;
            _authenticated = null;
          }
          _error = rejected
              ? l.embyLoginRequired
              : failureMessage(context, error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
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
            widget.server == null ? l.addServer : l.editServer,
            style: context.theme.typography.body.lg.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          FSelect<MediaServerType>.rich(
            key: const ValueKey('server-type'),
            label: Text(l.serverType),
            enabled: !_saving,
            format: (value) =>
                value == MediaServerType.emby ? 'Emby' : 'Jellyfin',
            control: .lifted(
              value: _type,
              onChange: (value) {
                if (value == null || value == _type) return;
                _type = value;
                _inputsChanged();
              },
            ),
            children: const [
              FSelectItem(
                title: Text('Jellyfin'),
                value: MediaServerType.jellyfin,
              ),
              FSelectItem(title: Text('Emby'), value: MediaServerType.emby),
            ],
          ),
          const SizedBox(height: 12),
          FTextField(
            key: const ValueKey('server-name'),
            enabled: !_saving,
            control: .managed(controller: _name),
            label: Text(l.serverName),
          ),
          const SizedBox(height: 12),
          FTextField(
            key: const ValueKey('server-url'),
            enabled: !_saving,
            control: .managed(controller: _url),
            label: Text(l.serverUrl),
            hint: '192.168.1.2:8096',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          if (_type == MediaServerType.emby) ...[
            FTextField(
              key: const ValueKey('server-username'),
              enabled: !_saving,
              control: .managed(controller: _username),
              label: Text(l.serverUsername),
            ),
            const SizedBox(height: 12),
            FTextField.password(
              key: const ValueKey('server-password'),
              enabled: !_saving,
              control: .managed(controller: _password),
              label: Text(l.serverPassword),
            ),
            const SizedBox(height: 8),
            Text(l.embyPasswordHelp, style: context.theme.typography.body.sm),
          ] else
            FTextField.password(
              key: const ValueKey('server-api-key'),
              enabled: !_saving,
              control: .managed(controller: _apiKey),
              label: Text(l.apiKey),
            ),
          const SizedBox(height: 8),
          FSwitch(
            key: const ValueKey('server-secure'),
            value: _secure,
            label: Text(l.secureConnection),
            onChange: _saving
                ? null
                : (value) {
                    _secure = value;
                    _inputsChanged();
                  },
          ),
          if (_result != null) ...[
            const SizedBox(height: 12),
            Text(
              '${l.connectedServer} · $_result',
              key: const ValueKey('server-test-result'),
              style: context.theme.typography.body.sm.copyWith(
                color: context.theme.colors.primary,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
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
                onPress: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(l.cancel),
              ),
              FButton(
                key: const ValueKey('server-test'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                variant: .outline,
                onPress: _busy ? null : () => _submit(save: false),
                child: Text(l.testConnection),
              ),
              FButton(
                key: const ValueKey('server-save'),
                builder: responsiveButtonContent,
                mainAxisSize: MainAxisSize.min,
                onPress: _busy ? null : () => _submit(save: true),
                child: Text(l.save),
              ),
            ],
          ),
        ],
      ),
    );
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
                Text(
                  server.type == MediaServerType.emby
                      ? 'Emby · ${server.username}'
                      : 'Jellyfin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.theme.typography.body.sm,
                ),
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
