import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/jellyfin_client.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import 'library_providers.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  String? _selectedViewId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final server = ref.watch(activeServerProvider);
    if (server == null) {
      return PageContent(
        children: [
          PageHeading(l.library, hideTitleOnMobile: true),
          EmptyNotice(
            l.noServer,
            child: FButton(
              builder: responsiveButtonContent,
              mainAxisSize: MainAxisSize.min,
              onPress: () => context.go('/settings?tab=servers'),
              child: Text(l.addServer),
            ),
          ),
        ],
      );
    }
    if (server.apiKey.isEmpty) {
      return PageContent(
        children: [
          PageHeading(l.library, hideTitleOnMobile: true),
          EmptyNotice(
            l.noApiKey,
            child: FButton(
              builder: responsiveButtonContent,
              mainAxisSize: MainAxisSize.min,
              onPress: () => context.go('/settings?tab=servers'),
              child: Text(l.servers),
            ),
          ),
        ],
      );
    }

    final data = ref.watch(libraryViewsProvider);
    return PageContent(
      children: [
        PageHeading(
          l.library,
          hideTitleOnMobile: true,
          action: FButton.icon(
            variant: .outline,
            size: .sm,
            semanticsLabel: l.refresh,
            onPress: () => ref.invalidate(libraryViewsProvider),
            child: const Icon(FLucideIcons.refreshCw),
          ),
        ),
        data.when(
          data: (library) {
            if (library.views.isEmpty) return EmptyNotice(l.emptyLibrary);
            final selected =
                library.views.any((view) => view.id == _selectedViewId)
                ? _selectedViewId!
                : library.views.first.id;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final view in library.views)
                      FButton(
                        builder: responsiveButtonContent,
                        mainAxisSize: MainAxisSize.min,
                        variant: view.id == selected ? .primary : .outline,
                        onPress: () =>
                            setState(() => _selectedViewId = view.id),
                        child: Text(view.name),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _ItemsGrid(
                  client: library.client,
                  query: (userId: library.userId, viewId: selected),
                ),
              ],
            );
          },
          loading: () => const LoadingNotice(),
          error: (error, _) => ErrorNotice(
            error,
            onRetry: () => ref.invalidate(libraryViewsProvider),
          ),
        ),
      ],
    );
  }
}

class _ItemsGrid extends ConsumerWidget {
  const _ItemsGrid({required this.client, required this.query});

  final JellyfinClient client;
  final ({String userId, String viewId}) query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final items = ref.watch(libraryItemsProvider(query));
    return items.when(
      data: (values) {
        if (values.isEmpty) return EmptyNotice(l.noItems);
        return AdaptiveGrid(
          children: [
            for (final item in values) _ItemCard(client: client, item: item),
          ],
        );
      },
      loading: () => const LoadingNotice(),
      error: (error, _) => ErrorNotice(
        error,
        onRetry: () => ref.invalidate(libraryItemsProvider(query)),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.client, required this.item});

  final JellyfinClient client;
  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final url = client.imageUrl(item);
    return Surface(
      padding: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: context.theme.style.borderRadius.md,
              child: url == null
                  ? const _Placeholder(icon: FLucideIcons.film)
                  : Image.network(
                      url,
                      headers: client.authHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const _Placeholder(icon: FLucideIcons.film),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.theme.typography.body.sm,
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.theme.colors.muted,
    child: Center(
      child: Icon(icon, color: context.theme.colors.mutedForeground),
    ),
  );
}
