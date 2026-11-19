import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../data/media_server/server_config.dart';
import '../../data/media_server/server_profile.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';

Future<bool?> chooseServerConfigExport(BuildContext context) async {
  var includeCredentials = false;
  return _showConfigDialog(
    context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final l = context.l10n;
        return _ConfigDialogContent(
          title: l.serverExport,
          confirmLabel: l.serverExportAction,
          onConfirm: () => Navigator.of(context).pop(includeCredentials),
          children: [
            FSwitch(
              key: const ValueKey('server-export-credentials'),
              label: Text(l.serverExportCredentials),
              value: includeCredentials,
              onChange: (value) => setState(() => includeCredentials = value),
            ),
            if (includeCredentials) ...[
              const SizedBox(height: 8),
              Text(l.serverExportCredentialsWarning),
            ],
          ],
        );
      },
    ),
  );
}

Future<bool> confirmServerConfigImport(
  BuildContext context,
  ServerConfigMerge preview,
) async =>
    await _showConfigDialog<bool>(
      context,
      builder: (context) {
        final l = context.l10n;
        return _ConfigDialogContent(
          title: l.serverImport,
          confirmLabel: l.serverImportAction,
          onConfirm: preview.added.isEmpty
              ? null
              : () => Navigator.of(context).pop(true),
          children: [
            _PreviewGroup(
              l.serverImportNew(preview.added.length),
              preview.added,
            ),
            const SizedBox(height: 12),
            _PreviewGroup(
              l.serverImportSkipped(preview.skipped.length),
              preview.skipped,
            ),
          ],
        );
      },
    ) ??
    false;

Future<T?> _showConfigDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showFDialog<T>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  builder: (context, style, animation) => FDialog(
    animation: animation,
    builder: (context, style) => builder(context),
  ),
);

class _ConfigDialogContent extends StatelessWidget {
  const _ConfigDialogContent({
    required this.title,
    required this.confirmLabel,
    required this.onConfirm,
    required this.children,
  });

  final String title;
  final String confirmLabel;
  final VoidCallback? onConfirm;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: context.theme.typography.body.lg.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            FButton(
              variant: .ghost,
              mainAxisSize: MainAxisSize.min,
              builder: responsiveButtonContent,
              onPress: () => Navigator.of(context).pop(),
              child: Text(
                onConfirm == null ? context.l10n.close : context.l10n.cancel,
              ),
            ),
            if (onConfirm != null)
              FButton(
                key: const ValueKey('confirm-server-config'),
                mainAxisSize: MainAxisSize.min,
                builder: responsiveButtonContent,
                onPress: onConfirm,
                child: Text(confirmLabel),
              ),
          ],
        ),
      ],
    ),
  );
}

class _PreviewGroup extends StatelessWidget {
  const _PreviewGroup(this.title, this.servers);

  final String title;
  final List<ServerProfile> servers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: context.theme.typography.body.sm.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      for (final server in servers) ...[
        const SizedBox(height: 6),
        Text(
          server.username.isEmpty
              ? server.name
              : '${server.name} · ${server.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          server.baseUrl,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.theme.typography.body.sm.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ],
    ],
  );
}
