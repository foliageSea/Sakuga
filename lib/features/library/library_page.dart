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
import '../detail/detail_page.dart';
import 'library_providers.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _scrollController = ScrollController();
  String? _selectedViewId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectView(String id) {
    if (_selectedViewId == id) return;
    setState(() => _selectedViewId = id);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

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
    final views = data.hasError ? null : data.value?.views;
    final hasViews = views != null && views.isNotEmpty;
    final activeViewId = hasViews
        ? (views.any((view) => view.id == _selectedViewId)
              ? _selectedViewId!
              : views.first.id)
        : null;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageScrollView(
        controller: _scrollController,
        headerGap: hasViews ? 20 : 0,
        header: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            if (hasViews)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final view in views)
                    FButton(
                      builder: responsiveButtonContent,
                      mainAxisSize: MainAxisSize.min,
                      variant: view.id == activeViewId ? .primary : .outline,
                      onPress: () => _selectView(view.id),
                      child: Text(view.name),
                    ),
                ],
              ),
          ],
        ),
        slivers: data.when(
          data: (library) => _librarySlivers(context, library, activeViewId),
          loading: () => const [SliverToBoxAdapter(child: LoadingNotice())],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: ErrorNotice(
                error,
                onRetry: () => ref.invalidate(libraryViewsProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
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

  List<Widget> _librarySlivers(
    BuildContext context,
    LibraryData library,
    String? viewId,
  ) {
    if (library.views.isEmpty || viewId == null) {
      return [
        SliverToBoxAdapter(child: EmptyNotice(context.l10n.emptyLibrary)),
      ];
    }
    return [
      _PagedGrid(
        client: library.client,
        query: (userId: library.userId, viewId: viewId),
        onTap: (item, posterUrl) => context.go(
          '/library/${item.id}',
          extra: DetailRouteExtra(item: item, posterUrl: posterUrl),
        ),
      ),
    ];
  }
}

typedef _OpenLibraryItem = void Function(JellyfinItem item, String? posterUrl);

class _PagedGrid extends ConsumerWidget {
  const _PagedGrid({
    required this.client,
    required this.query,
    required this.onTap,
  });

  final JellyfinClient client;
  final LibraryQuery query;
  final _OpenLibraryItem onTap;

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
    final items = _uniqueItems(state.items);
    if (isMobileLayout(context)) {
      return SliverToBoxAdapter(
        child: _MobileMasonryGrid(client: client, items: items, onTap: onTap),
      );
    }
    final columns = _columns(context);
    final rows = (items.length / columns).ceil();
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, row) {
        final start = row * columns;
        final end = math.min(start + columns, items.length);
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
                          key: ValueKey(
                            'library-desktop-card-${items[start + column].id}',
                          ),
                          client: client,
                          item: items[start + column],
                          progress: items[start + column].progressFraction,
                          heroTag: posterHeroTag(items[start + column].id),
                          onPosterTap: (posterUrl) =>
                              onTap(items[start + column], posterUrl),
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

  List<JellyfinItem> _uniqueItems(List<JellyfinItem> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }

  int _columns(BuildContext context) {
    final width =
        math.min(MediaQuery.sizeOf(context).width, 1440) -
        pagePadding(context) * 2;
    return ((width + 16) / (280 + 16)).floor().clamp(1, 4);
  }
}

class _MobileMasonryGrid extends StatelessWidget {
  const _MobileMasonryGrid({
    required this.client,
    required this.items,
    required this.onTap,
  });

  static const _spacing = 12.0;
  static const _cardChromeHeight = 55.0;

  final JellyfinClient client;
  final List<JellyfinItem> items;
  final _OpenLibraryItem onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - _spacing) / 2;
      final columns = <List<JellyfinItem>>[[], []];
      final heights = [0.0, 0.0];
      for (final item in items) {
        final column = heights[0] <= heights[1] ? 0 : 1;
        columns[column].add(item);
        heights[column] +=
            cardWidth / item.posterAspectRatio + _cardChromeHeight + _spacing;
      }
      return Row(
        key: const ValueKey('library-mobile-masonry'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns.length; column++) ...[
            if (column > 0) const SizedBox(width: _spacing),
            Expanded(
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < columns[column].length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: _spacing),
                    MediaPosterCard(
                      key: ValueKey(
                        'library-mobile-card-${columns[column][index].id}',
                      ),
                      client: client,
                      item: columns[column][index],
                      progress: columns[column][index].progressFraction,
                      aspectRatio: columns[column][index].posterAspectRatio,
                      heroTag: posterHeroTag(columns[column][index].id),
                      onPosterTap: (posterUrl) =>
                          onTap(columns[column][index], posterUrl),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
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
