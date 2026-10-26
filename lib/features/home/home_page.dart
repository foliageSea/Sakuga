import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/jellyfin_client.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../data/jellyfin/server_profile.dart';
import '../../data/jellyfin/server_repository.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../library/library_providers.dart';
import '../player/player_route.dart';
import 'home_providers.dart';

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
            final library = ref.watch(libraryViewsProvider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ServerSummary(server: items.first),
                ...library.when(
                  data: (data) => [
                    _MediaSection(
                      client: data.client,
                      title: l.continueWatching,
                      items: ref.watch(resumeItemsProvider),
                      onRetry: () => ref.invalidate(resumeItemsProvider),
                      onTap: (item) => _resume(context, item),
                    ),
                    _MediaSection(
                      client: data.client,
                      title: l.recentlyAdded,
                      items: ref.watch(latestItemsProvider),
                      onRetry: () => ref.invalidate(latestItemsProvider),
                      onTap: (item) => context.go('/library/${item.id}'),
                    ),
                  ],
                  loading: () => const [
                    Padding(
                      padding: EdgeInsets.only(top: 28),
                      child: LoadingNotice(),
                    ),
                  ],
                  error: (error, _) => [
                    Padding(
                      padding: const EdgeInsets.only(top: 28),
                      child: ErrorNotice(
                        error,
                        onRetry: () => ref.invalidate(libraryViewsProvider),
                      ),
                    ),
                  ],
                ),
              ],
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

/// Resumes playback where the user left off; series open their detail page.
void _resume(BuildContext context, JellyfinItem item) {
  if (item.isSeries) {
    context.go('/library/${item.id}');
  } else {
    context.push(playerLocation(item.id));
  }
}

class _ServerSummary extends StatelessWidget {
  const _ServerSummary({required this.server});

  final ServerProfile server;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
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
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection({
    required this.client,
    required this.title,
    required this.items,
    required this.onRetry,
    required this.onTap,
  });

  final JellyfinClient client;
  final String title;
  final AsyncValue<List<JellyfinItem>> items;
  final VoidCallback onRetry;
  final ValueChanged<JellyfinItem> onTap;

  @override
  Widget build(BuildContext context) {
    return items.when(
      data: (values) {
        if (values.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.theme.typography.body.lg.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < values.length; index++) ...[
                      if (index > 0) const SizedBox(width: 12),
                      Builder(
                        builder: (context) {
                          final item = values[index];
                          final percentage = item.playedPercentage;
                          final landscape = item.isEpisode;
                          return SizedBox(
                            width: landscape ? 260 : 160,
                            child: MediaPosterCard(
                              client: client,
                              item: item,
                              progress: percentage == null
                                  ? null
                                  : percentage / 100,
                              aspectRatio: landscape
                                  ? item.thumbnailAspectRatio
                                  : null,
                              onTap: () => onTap(item),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 28),
        child: LoadingNotice(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: ErrorNotice(error, onRetry: onRetry),
      ),
    );
  }
}
