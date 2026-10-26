import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/server_repository.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final servers = ref.watch(serversProvider);
    return PageContent(
      children: [
        PageHeading(l.home, hideTitleOnMobile: true),
        servers.when(
          data: (items) {
            if (items.isEmpty) {
              return EmptyNotice(
                l.noServer,
                child: FButton(
                  builder: responsiveButtonContent,
                  mainAxisSize: MainAxisSize.min,
                  onPress: () => context.go('/settings?tab=servers'),
                  child: Text(l.addServer),
                ),
              );
            }
            final server = items.first;
            return Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: context.theme.typography.body.lg.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    server.baseUrl,
                    style: context.theme.typography.body.sm.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FButton(
                    builder: responsiveButtonContent,
                    mainAxisSize: MainAxisSize.min,
                    variant: .outline,
                    onPress: () => context.go('/settings?tab=servers'),
                    child: Text(l.servers),
                  ),
                ],
              ),
            );
          },
          loading: () => const LoadingNotice(),
          error: (error, _) => ErrorNotice(
            error,
            onRetry: () => ref.invalidate(serversProvider),
          ),
        ),
      ],
    );
  }
}
