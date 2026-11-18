import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_exception.dart';
import '../../data/emby/emby_auth.dart';
import '../../data/fnmovie/fnmovie_auth.dart';
import '../../data/jellyfin/jellyfin_auth.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/server_probe.dart';
import '../../data/media_server/server_profile.dart';
import '../../data/media_server/server_repository.dart';
import '../../data/ugreen/ugreen_auth.dart';
import '../../data/ugreen/ugreen_transport.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';

final ugreenFingerprintProbeProvider =
    Provider<Future<String> Function(String)>(
      (ref) => fetchUgreenCertificateFingerprint,
    );

String _serverTypeLabel(BuildContext context, MediaServerType type) =>
    switch (type) {
      MediaServerType.jellyfin => 'Jellyfin',
      MediaServerType.emby => 'Emby',
      MediaServerType.fnmovie => context.l10n.serverTypeFnMovie,
      MediaServerType.ugreen => context.l10n.serverTypeUgreen,
    };

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
  late final TextEditingController _fingerprint;
  late MediaServerType _type;
  bool get _isUgreen => _type == MediaServerType.ugreen;
  late bool _secure;
  late bool _account;
  bool _identityReset = false;
  bool _busy = false;
  bool _fetchingFingerprint = false;
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
    _fingerprint = TextEditingController(
      text: server?.certificateFingerprint ?? '',
    );
    _type = server?.type ?? MediaServerType.jellyfin;
    _account = server?.usesAccount ?? true;
    _secure = isSecureBaseUrl(server?.baseUrl ?? '');
    for (final controller in [
      _name,
      _url,
      _apiKey,
      _username,
      _password,
      _fingerprint,
    ]) {
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

  void _changeAuthentication(bool account) {
    _account = account;
    _identityReset = true;
    _apiKey.clear();
    _username.clear();
    _password.clear();
    if (!_isUgreen) _fingerprint.clear();
    _sessionRejected = false;
    _inputsChanged();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _url,
      _apiKey,
      _username,
      _password,
      _fingerprint,
    ]) {
      controller.removeListener(_inputsChanged);
      controller.dispose();
    }
    super.dispose();
  }

  bool _acceptsResponse(int revision) =>
      mounted &&
      revision == _revision &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _fetchFingerprint() async {
    if (_busy || !_isUgreen) return;
    final l = context.l10n;
    final String baseUrl;
    try {
      baseUrl = normalizeUgreenBaseUrl(_url.text);
    } on FormatException {
      setState(() => _error = l.serverUrlInvalid);
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = _fetchingFingerprint = true;
      _error = null;
    });
    try {
      final observed = await ref.read(ugreenFingerprintProbeProvider)(baseUrl);
      if (!_acceptsResponse(revision)) return;
      setState(() => _fetchingFingerprint = false);
      final confirmed = await showFDialog<bool>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        builder: (context, style, animation) => FDialog(
          animation: animation,
          builder: (context, style) =>
              _FingerprintPreview(fingerprint: observed),
        ),
      );
      if (confirmed == true && _acceptsResponse(revision)) {
        _fingerprint.text = observed;
      }
    } catch (_) {
      if (_acceptsResponse(revision)) {
        setState(() => _error = l.ugreenFingerprintFetchError);
      }
    } finally {
      if (mounted) setState(() => _busy = _fetchingFingerprint = false);
    }
  }

  Future<void> _submit({required bool save}) async {
    if (_busy) return;
    final l = context.l10n;
    if (save && _name.text.trim().isEmpty) {
      setState(() => _error = l.serverNameRequired);
      return;
    }
    String baseUrl;
    var fingerprint = '';
    if (_isUgreen) {
      try {
        fingerprint = normalizeUgreenFingerprint(_fingerprint.text);
      } on FormatException {
        setState(() => _error = l.ugreenFingerprintInvalid);
        return;
      }
    }
    try {
      baseUrl = _isUgreen
          ? normalizeUgreenBaseUrl(_url.text)
          : composeBaseUrl(_url.text, secure: _secure);
    } on FormatException {
      setState(() => _error = l.serverUrlInvalid);
      return;
    }
    final revision = _revision;
    final old = widget.server;
    final username = _username.text.trim();
    final password = _password.text;
    final account = _account;
    final identityChanged =
        old == null ||
        _identityReset ||
        old.type != _type ||
        old.usesAccount != account ||
        old.baseUrl != baseUrl ||
        (_isUgreen && old.certificateFingerprint != fingerprint) ||
        (account && old.username != username);
    final needsLogin =
        account &&
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
        apiKey: account ? '' : _apiKey.text.trim(),
        accessToken: account && !identityChanged ? old.accessToken : '',
        userId: account && !identityChanged ? old.userId : '',
        username: account ? username : '',
        deviceId: account && !identityChanged ? old.deviceId : '',
        remoteServerId: account && !identityChanged ? old.remoteServerId : '',
        certificateFingerprint: fingerprint,
      );
      if (needsLogin) {
        if (_authenticated != null) {
          profile = _authenticated!;
        } else if (_isUgreen) {
          final deviceId = await ref.read(ugreenDeviceIdProvider.future);
          if (!_acceptsResponse(revision)) return;
          final result = await ref
              .read(ugreenAuthProvider)
              .authenticate(
                baseUrl: baseUrl,
                username: username,
                password: password,
                deviceId: deviceId,
                fingerprint: fingerprint,
              );
          if (!_acceptsResponse(revision)) return;
          profile = profile.copyWith(
            id:
                !identityChanged &&
                    (old.userId != result.userId ||
                        old.remoteServerId != result.remoteServerId)
                ? DateTime.now().microsecondsSinceEpoch.toString()
                : profile.id,
            accessToken: result.accessToken,
            userId: result.userId,
            username: result.username,
            deviceId: deviceId,
            remoteServerId: result.remoteServerId,
          );
          await ref
              .read(mediaServerFactoryProvider)
              .createClient(profile)
              .users();
          if (!_acceptsResponse(revision)) return;
          _authenticated = profile;
        } else if (_type == MediaServerType.fnmovie) {
          final result = await ref
              .read(fnMovieAuthProvider)
              .authenticate(
                baseUrl: baseUrl,
                username: username,
                password: password,
              );
          if (!_acceptsResponse(revision)) return;
          profile = profile.copyWith(
            baseUrl: result.baseUrl,
            accessToken: result.accessToken,
            // fnOS Media login returns a token, not a distinct account GUID.
            userId: profile.id,
          );
          _authenticated = profile;
        } else {
          final emby = _type == MediaServerType.emby;
          final deviceId = await ref.read(
            emby
                ? embyDeviceIdProvider.future
                : jellyfinDeviceIdProvider.future,
          );
          if (!_acceptsResponse(revision)) return;
          final result = await (emby
              ? ref
                    .read(embyAuthProvider)
                    .authenticate(
                      baseUrl: baseUrl,
                      username: username,
                      password: password,
                      deviceId: deviceId,
                    )
              : ref
                    .read(jellyfinAuthProvider)
                    .authenticate(
                      baseUrl: baseUrl,
                      username: username,
                      password: password,
                      deviceId: deviceId,
                    ));
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
            type: _type,
            accessToken: result.accessToken,
            userId: result.userId,
            username: result.username,
            deviceId: deviceId,
            remoteServerId: result.remoteServerId,
          );
          _authenticated = profile;
        }
      } else if (!save && account) {
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
            account &&
            (error is AppException &&
                    error.kind == FailureKind.auth &&
                    error.cause != 403 ||
                error is DioException && error.response?.statusCode == 401);
        setState(() {
          if (rejected) {
            _sessionRejected = true;
            _authenticated = null;
          }
          _error = rejected
              ? l.serverLoginRequired
              : _isUgreen &&
                    (error is TlsException ||
                        (error is DioException &&
                            error.error is TlsException) ||
                        (error is AppException && error.cause is TlsException))
              ? l.ugreenCertificateError
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
            format: (value) => _serverTypeLabel(context, value),
            control: .lifted(
              value: _type,
              onChange: (value) {
                if (value == null || value == _type) return;
                _type = value;
                _changeAuthentication(true);
              },
            ),
            children: [
              for (final type in MediaServerType.values)
                FSelectItem(
                  title: Text(_serverTypeLabel(context, type)),
                  value: type,
                ),
            ],
          ),
          if (_type == MediaServerType.jellyfin) ...[
            const SizedBox(height: 12),
            FSelect<bool>.rich(
              key: const ValueKey('server-auth-method'),
              label: Text(l.serverAuthMethod),
              enabled: !_saving,
              format: (value) => value ? l.serverAccountPassword : l.apiKey,
              control: .lifted(
                value: _account,
                onChange: (value) {
                  if (value == null || value == _account) return;
                  _changeAuthentication(value);
                },
              ),
              children: [
                FSelectItem(title: Text(l.serverAccountPassword), value: true),
                FSelectItem(title: Text(l.apiKey), value: false),
              ],
            ),
          ],
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
            hint: switch (_type) {
              MediaServerType.ugreen => '192.168.1.2:9443',
              MediaServerType.fnmovie => '192.168.1.2',
              _ => '192.168.1.2:8096',
            },
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          if (_account) ...[
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
            Text(
              _isUgreen ? l.ugreenAccountHelp : l.serverPasswordHelp,
              style: context.theme.typography.body.sm,
            ),
          ] else
            FTextField.password(
              key: const ValueKey('server-api-key'),
              enabled: !_saving,
              control: .managed(controller: _apiKey),
              label: Text(l.apiKey),
            ),
          const SizedBox(height: 8),
          if (_isUgreen) ...[
            FTextField(
              key: const ValueKey('ugreen-fingerprint'),
              enabled: !_saving,
              control: .managed(controller: _fingerprint),
              label: Text(l.ugreenFingerprint),
            ),
            const SizedBox(height: 8),
            Text(
              l.ugreenFingerprintHelp,
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FButton(
                key: const ValueKey('ugreen-fetch-fingerprint'),
                mainAxisSize: MainAxisSize.min,
                variant: .outline,
                onPress: _busy ? null : _fetchFingerprint,
                child: Text(
                  _fetchingFingerprint
                      ? l.ugreenFingerprintFetching
                      : l.ugreenFingerprintFetch,
                ),
              ),
            ),
            if (widget.server?.type == MediaServerType.ugreen) ...[
              const SizedBox(height: 12),
              FButton(
                key: const ValueKey('ugreen-relogin'),
                variant: .ghost,
                onPress: _busy
                    ? null
                    : () {
                        _sessionRejected = true;
                        _inputsChanged();
                        _submit(save: false);
                      },
                child: Text(l.ugreenRelogin),
              ),
            ],
          ] else
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

class _FingerprintPreview extends StatefulWidget {
  const _FingerprintPreview({required this.fingerprint});

  final String fingerprint;

  @override
  State<_FingerprintPreview> createState() => _FingerprintPreviewState();
}

class _FingerprintPreviewState extends State<_FingerprintPreview> {
  bool? _copied;

  Future<void> _copy() async {
    var copied = false;
    try {
      await Clipboard.setData(ClipboardData(text: widget.fingerprint));
      copied = true;
    } catch (_) {
      // Keep the preview open even if the platform clipboard is unavailable.
    }
    if (mounted) setState(() => _copied = copied);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.ugreenFingerprintTitle,
            style: theme.typography.body.lg.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(l.ugreenFingerprintUnverified),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text(widget.fingerprint)),
              const SizedBox(width: 8),
              FTooltip(
                tipBuilder: (context, controller) =>
                    Text(l.ugreenFingerprintCopy),
                child: FButton.icon(
                  key: const ValueKey('ugreen-copy-fingerprint'),
                  variant: .outline,
                  semanticsLabel: l.ugreenFingerprintCopy,
                  onPress: _copy,
                  child: const Icon(FLucideIcons.copy),
                ),
              ),
            ],
          ),
          if (_copied case final copied?) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(copied ? l.copied : l.ugreenFingerprintCopyError),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              FButton(
                key: const ValueKey('ugreen-close-fingerprint'),
                mainAxisSize: MainAxisSize.min,
                variant: .ghost,
                onPress: () => Navigator.of(context).pop(false),
                child: Text(l.close),
              ),
              FButton(
                key: const ValueKey('ugreen-use-fingerprint'),
                mainAxisSize: MainAxisSize.min,
                onPress: () => Navigator.of(context).pop(true),
                child: Text(l.ugreenFingerprintUse),
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              FLucideIcons.server,
              size: 20,
              color: active
                  ? context.theme.colors.primary
                  : context.theme.colors.mutedForeground,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_serverTypeLabel(context, server.type)}'
                  '${server.usesAccount ? ' · ${server.username}' : ''}',
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
