import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/jellyfin_client.dart';
import '../../data/jellyfin/jellyfin_models.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
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
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeading(
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
          ),
          ...data.when(
            data: (library) => _librarySlivers(context, library),
            loading: () => [const SliverToBoxAdapter(child: LoadingNotice())],
            error: (error, _) => [
              SliverToBoxAdapter(
                child: ErrorNotice(
                  error,
                  onRetry: () => ref.invalidate(libraryViewsProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter > 480) return false;
    final library = ref.read(libraryViewsProvider).value;
    if (library == null || library.views.isEmpty) return false;
    final viewId = library.views.any((view) => view.id == _selectedViewId)
        ? _selectedViewId!
        : library.views.first.id;
    unawaited(
      ref
          .read(
            libraryItemsProvider((userId: library.userId, viewId: viewId))
                .notifier,
          )
          .loadMore(),
    );
    return false;
  }

  List<Widget> _librarySlivers(BuildContext context, LibraryData library) {
    if (library.views.isEmpty) {
      return [
        SliverToBoxAdapter(child: EmptyNotice(context.l10n.emptyLibrary)),
      ];
    }
    final viewId = library.views.any((view) => view.id == _selectedViewId)
        ? _selectedViewId!
        : library.views.first.id;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final view in library.views)
                FButton(
                  builder: responsiveButtonContent,
                  mainAxisSize: MainAxisSize.min,
                  variant: view.id == viewId ? .primary : .outline,
                  onPress: () => setState(() => _selectedViewId = view.id),
                  child: Text(view.name),
                ),
            ],
          ),
        ),
      ),
      _PagedGrid(
        client: library.client,
        query: (userId: library.userId, viewId: viewId),
        onTap: (item) => context.go('/library/${item.id}'),
      ),
    ];
  }
}

class _PagedGrid extends ConsumerWidget {
  const _PagedGrid({
    required this.client,
    required this.query,
    required this.onTap,
  });

  final JellyfinClient client;
  final LibraryQuery query;
  final ValueChanged<JellyfinItem> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryItemsProvider(query));
    return SliverMainAxisGroup(
      slivers: state.when(
        data: (value) => [
          _grid(context, value),
          SliverToBoxAdapter(
            child: _PageFooter(query: query, state: value),
          ),
        ],
        loading: () => [const SliverToBoxAdapter(child: LoadingNotice())],
        error: (error, _) => [
          SliverToBoxAdapter(
            child: ErrorNotice(
              error,
              onRetry: () => ref.invalidate(libraryItemsProvider(query)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, LibraryItemsState state) {
    if (state.items.isEmpty) {
      return SliverToBoxAdapter(child: EmptyNotice(context.l10n.noItems));
    }
    final columns = _columns(context);
    final rows = (state.items.length / columns).ceil();
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, row) {
        final start = row * columns;
        final end = math.min(start + columns, state.items.length);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 16),
                Expanded(
                  child: start + column < end
                      ? MediaPosterCard(
                          client: client,
                          item: state.items[start + column],
                          onTap: () => onTap(state.items[start + column]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      }, childCount: rows),
    );
  }

  int _columns(BuildContext context) {
    final width =
        math.min(MediaQuery.sizeOf(context).width, 1440) -
        pagePadding(context) * 2;
    return ((width + 16) / (280 + 16)).floor().clamp(1, 4);
  }
}

class _PageFooter extends ConsumerWidget {
  const _PageFooter({required this.query, required this.state});

  final LibraryQuery query;
  final LibraryItemsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (state.loadingMore) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FCircularProgress(),
            const SizedBox(width: 12),
            Text(l.loading),
          ],
        ),
      );
    }
    final error = state.loadMoreError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: ErrorNotice(
          error,
          onRetry: () => ref
              .read(libraryItemsProvider(query).notifier)
              .loadMore(retry: true),
        ),
      );
    }
    if (!state.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Center(
        child: FButton(
          builder: responsiveButtonContent,
          variant: .outline,
          mainAxisSize: MainAxisSize.min,
          onPress: () =>
              ref.read(libraryItemsProvider(query).notifier).loadMore(),
          child: Text(l.loadMore),
        ),
      ),
    );
  }
}
