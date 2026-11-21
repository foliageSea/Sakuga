import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/media_server/media_server_client.dart';
import '../../data/media_server/media_server_factory.dart';
import '../../data/media_server/media_models.dart';
import '../../data/media_server/server_profile.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/poster_background.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../detail/detail_page.dart';
import 'library_filters.dart';
import 'library_providers.dart';
import 'library_server_picker.dart';
import 'library_toolbar.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  static const _debounceDelay = Duration(milliseconds: 300);

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _searchTerm = '';
  String? _selectedViewId;
  String? _selectedGenre;
  bool? _isPlayed;
  int? _selectedYear;
  MediaSort _sort = MediaSort.name;
  bool _descending = false;
  bool _showFilters = false;
  bool _listView = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    final term = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (term == _searchTerm) return;
    if (term.isEmpty) {
      _search(term);
    } else {
      _searchDebounce = Timer(_debounceDelay, () => _search(term));
    }
  }

  void _search(String term) {
    _searchDebounce?.cancel();
    term = term.trim();
    if (!mounted || term == _searchTerm) return;
    setState(() => _searchTerm = term);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _selectView(String id) {
    if (_selectedViewId == id) return;
    setState(() {
      _selectedViewId = id;
      _selectedGenre = null;
      _isPlayed = null;
      _selectedYear = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _selectGenre(String? genre) {
    if (_selectedGenre == genre) return;
    setState(() => _selectedGenre = genre);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _updateView(VoidCallback update) {
    setState(update);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _clearFilters() => _updateView(() {
    _selectedGenre = null;
    _isPlayed = null;
    _selectedYear = null;
  });

  LibraryQuery _query(LibraryData library, String viewId) {
    final type = library.client.server.type;
    final advanced = type.supportsLibraryOptions;
    return LibraryQuery(
      userId: library.userId,
      viewId: viewId,
      genre: type.supportsLibraryGenreFilter ? _selectedGenre : null,
      isPlayed: advanced ? _isPlayed : null,
      year: advanced ? _selectedYear : null,
      sort: advanced ? _sort : MediaSort.name,
      descending: advanced && _descending,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeServerProvider, (previous, next) {
      if (previous?.id == next?.id) return;
      _searchDebounce?.cancel();
      setState(() {
        _searchTerm = '';
        _selectedViewId = null;
        _selectedGenre = null;
        _isPlayed = null;
        _selectedYear = null;
        _sort = MediaSort.name;
        _descending = false;
      });
      _searchController.clear();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
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
    final mobileShell =
        isMobileLayout(context) &&
        WindowPosterBackgroundScope.hasShell(context);
    final serverButton = LibraryServerHeaderScope.hasAction(context)
        ? null
        : const LibraryServerAction();
    if (!ref.watch(mediaServerClientProvider(server)).isConfigured) {
      return PageContent(
        children: [
          PageHeading(l.library, hideTitleOnMobile: true),
          if (serverButton != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: serverButton,
            ),
            const SizedBox(height: 12),
          ],
          EmptyNotice(
            server.usesAccount ? l.serverLoginRequired : l.noApiKey,
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
    final views = data.hasError || data.isReloading ? null : data.value?.views;
    final hasViews = views != null && views.isNotEmpty;
    final activeViewId = hasViews
        ? (views.any((view) => view.id == _selectedViewId)
              ? _selectedViewId!
              : views.first.id)
        : null;
    final query = activeViewId == null
        ? null
        : _query(data.requireValue, activeViewId);
    final viewChips = hasViews && _searchTerm.isEmpty
        ? Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final view in views)
                FButton(
                  builder: responsiveButtonContent,
                  mainAxisSize: MainAxisSize.min,
                  variant: view.id == activeViewId ? .secondary : .ghost,
                  selected: view.id == activeViewId,
                  onPress: () => _selectView(view.id),
                  child: Text(view.name),
                ),
            ],
          )
        : null;
    final toolbar = LibraryToolbar(
      showFilters: server.type.supportsLibraryGenreFilter,
      showSort: server.type.supportsLibraryOptions,
      filtersVisible: _showFilters,
      hasFilters:
          _selectedGenre != null || _isPlayed != null || _selectedYear != null,
      listView: _listView,
      sort: _sort,
      descending: _descending,
      onToggleFilters: () => setState(() => _showFilters = !_showFilters),
      onView: (value) => _updateView(() => _listView = value),
      onSort: (sort, descending) => _updateView(() {
        _sort = sort;
        _descending = descending;
      }),
      onClear: _clearFilters,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageScrollView(
        controller: _scrollController,
        headerGap: 12,
        header: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!mobileShell)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.library,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.body.xl.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (serverButton != null) ...[
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 280,
                                ),
                                child: serverButton,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          FButton.icon(
                            key: const ValueKey('library-refresh'),
                            variant: .ghost,
                            size: .sm,
                            semanticsLabel: l.refresh,
                            onPress: () => ref.invalidate(libraryViewsProvider),
                            child: const Icon(FLucideIcons.refreshCw),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (mobileShell && serverButton != null) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: serverButton,
              ),
              const SizedBox(height: 12),
            ],
            if (viewChips != null) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final count = query == null
                      ? const SizedBox.shrink()
                      : _LibraryCount(query: query);
                  if (constraints.maxWidth >= 760) {
                    return Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(child: viewChips),
                              const SizedBox(width: 12),
                              count,
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        toolbar,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      viewChips,
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: count),
                          toolbar,
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
            if (viewChips == null)
              Align(alignment: Alignment.centerRight, child: toolbar),
            if (_showFilters || !server.type.supportsLibraryOptions) ...[
              const SizedBox(height: 12),
              FTextField(
                key: const ValueKey('library-search'),
                control: .managed(controller: _searchController),
                hint: l.searchHint,
                textInputAction: TextInputAction.search,
                clearable: (value) => value.text.isNotEmpty,
                onSubmit: _search,
                // Blend into the page instead of drawing a filled card behind the
                // input; the default forui style fills it with the card color.
                style: .delta(color: .delta([.base(const Color(0x00000000))])),
              ),
              const SizedBox(height: 8),
            ],
            if (server.type.supportsLibraryGenreFilter &&
                _showFilters &&
                _searchTerm.isEmpty &&
                query != null)
              LibraryFilterPanel(
                key: ValueKey((
                  data.requireValue.client.server.id,
                  activeViewId,
                )),
                query: query,
                showAdvancedFilters: server.type.supportsLibraryOptions,
                onGenre: _selectGenre,
                onPlayed: (value) => _updateView(() => _isPlayed = value),
                onYear: (value) => _updateView(() => _selectedYear = value),
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
    if (_searchTerm.isNotEmpty) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.extentAfter > 480) return false;
    final data = ref.read(libraryViewsProvider);
    final library = data.value;
    if (data.isReloading || library == null || library.views.isEmpty) {
      return false;
    }
    final viewId = library.views.any((view) => view.id == _selectedViewId)
        ? _selectedViewId!
        : library.views.first.id;
    unawaited(
      ref
          .read(libraryItemsProvider(_query(library, viewId)).notifier)
          .loadMore(),
    );
    return false;
  }

  List<Widget> _librarySlivers(
    BuildContext context,
    LibraryData library,
    String? viewId,
  ) {
    if (_searchTerm.isNotEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.only(top: 24),
          sliver: _SearchGrid(
            client: library.client,
            term: _searchTerm,
            listView: _listView,
          ),
        ),
      ];
    }
    if (library.views.isEmpty || viewId == null) {
      return [const _LibraryEmptyState()];
    }
    return [
      SliverPadding(
        // Leave room inside the viewport for the first row's 3D hover effect.
        padding: const EdgeInsets.only(top: 24),
        sliver: _PagedGrid(
          client: library.client,
          query: _query(library, viewId),
          listView: _listView,
          onTap: (item, posterUrl) => context.go(
            '/library/${item.id}',
            extra: DetailRouteExtra(item: item, posterUrl: posterUrl),
          ),
        ),
      ),
    ];
  }
}

class _LibraryCount extends ConsumerWidget {
  const _LibraryCount({required this.query});
  final LibraryQuery query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryItemsProvider(query));
    final count = state.value?.totalRecordCount;
    return Text(
      count == null ? '—' : context.l10n.libraryCount(count),
      key: const ValueKey('library-count'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.theme.typography.body.sm.copyWith(
        color: context.theme.colors.mutedForeground,
      ),
    );
  }
}

typedef _OpenLibraryItem = void Function(MediaItem item, String? posterUrl);

class _PagedGrid extends ConsumerWidget {
  const _PagedGrid({
    required this.client,
    required this.query,
    required this.onTap,
    this.listView = false,
  });

  final MediaServerClient client;
  final LibraryQuery query;
  final _OpenLibraryItem onTap;
  final bool listView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryItemsProvider(query));
    return SliverMainAxisGroup(
      slivers: state.when(
        data: (value) => [
          _LibraryGrid(
            client: client,
            items: value.items,
            listView: listView,
            onTap: onTap,
          ),
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
}

class _SearchGrid extends ConsumerWidget {
  const _SearchGrid({
    required this.client,
    required this.term,
    this.listView = false,
  });

  final MediaServerClient client;
  final String term;
  final bool listView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = searchResultsProvider((
      serverId: client.server.id,
      term: term,
    ));
    return ref
        .watch(results)
        .when(
          data: (items) => _LibraryGrid(
            client: client,
            items: items,
            listView: listView,
            onTap: (item, posterUrl) => context.go(
              '/library/${item.id}',
              extra: DetailRouteExtra(item: item, posterUrl: posterUrl),
            ),
          ),
          loading: () => const SliverToBoxAdapter(child: LoadingNotice()),
          error: (error, _) => SliverToBoxAdapter(
            child: ErrorNotice(error, onRetry: () => ref.invalidate(results)),
          ),
        );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState();

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FLucideIcons.inbox,
            size: 32,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(height: 16),
          Text(context.l10n.noResults, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.client,
    required this.items,
    required this.onTap,
    this.listView = false,
  });

  final MediaServerClient client;
  final List<MediaItem> items;
  final _OpenLibraryItem onTap;
  final bool listView;

  @override
  Widget build(BuildContext context) {
    if (this.items.isEmpty) {
      return const _LibraryEmptyState();
    }
    final items = _uniqueItems(this.items);
    if (listView) {
      return SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => _LibraryListItem(
          key: ValueKey('library-list-item-${items[index].id}'),
          client: client,
          item: items[index],
          onTap: onTap,
        ),
      );
    }
    final mobile = isMobileLayout(context);
    final spacing = mobile ? 12.0 : 20.0;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = mobile
            ? 2
            : ((constraints.crossAxisExtent + spacing) / 240).floor().clamp(
                2,
                6,
              );
        final rows = (items.length / columns).ceil();
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, row) {
            final start = row * columns;
            final end = math.min(start + columns, items.length);
            return Padding(
              padding: EdgeInsets.only(bottom: mobile ? 12 : 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) SizedBox(width: spacing),
                    Expanded(
                      child: start + column < end
                          ? _LibraryPoster(
                              cardKey: ValueKey(
                                'library-${mobile ? 'mobile' : 'desktop'}-card-${items[start + column].id}',
                              ),
                              client: client,
                              item: items[start + column],
                              onTap: onTap,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            );
          }, childCount: rows),
        );
      },
    );
  }

  List<MediaItem> _uniqueItems(List<MediaItem> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add(item.id)) item,
    ];
  }
}

String? _libraryMetadata(BuildContext context, MediaItem item) {
  final parts = <String>[
    if (item.productionYear != null) '${item.productionYear}',
    if (item.isSeries &&
        item.recursiveItemCount != null &&
        item.recursiveItemCount! > 0)
      context.l10n.libraryEpisodeCount(item.recursiveItemCount!)
    else if (item.isSeries && item.childCount != null && item.childCount! > 0)
      context.l10n.librarySeasonCount(item.childCount!),
    if (!item.isSeries && item.runtime != null)
      context.l10n.libraryDuration(item.runtime!.inMinutes),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

class _LibraryPoster extends StatelessWidget {
  const _LibraryPoster({
    required this.cardKey,
    required this.client,
    required this.item,
    required this.onTap,
  });
  final Key cardKey;
  final MediaServerClient client;
  final MediaItem item;
  final _OpenLibraryItem onTap;

  @override
  Widget build(BuildContext context) {
    return MediaPosterCard(
      key: cardKey,
      client: client,
      item: item,
      subtitle: _libraryMetadata(context, item),
      showRating: true,
      reserveMetadataSpace: true,
      progress: item.progressFraction,
      heroTag: posterHeroTag(item.id),
      onPosterTap: (posterUrl) => onTap(item, posterUrl),
    );
  }
}

class _LibraryListItem extends StatelessWidget {
  const _LibraryListItem({
    required this.client,
    required this.item,
    required this.onTap,
    super.key,
  });
  final MediaServerClient client;
  final MediaItem item;
  final _OpenLibraryItem onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final metadata = _libraryMetadata(context, item);
    final rating = item.communityRating;
    final progress = item.progressFraction;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          final gap = wide ? 16.0 : 12.0;
          final progressBar = progress == null
              ? null
              : SizedBox(
                  key: ValueKey('library-list-progress-${item.id}'),
                  width: 144,
                  child: MediaProgressBar(value: progress),
                );
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colors.card.withValues(
                alpha: theme.colors.brightness == Brightness.dark ? 0.32 : 0.4,
              ),
              borderRadius: theme.style.borderRadius.lg,
            ),
            child: FButton(
              variant: .ghost,
              style: .delta(
                contentStyle: .delta(
                  padding: .value(
                    EdgeInsets.symmetric(
                      horizontal: wide ? 16 : 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              builder: responsiveButtonContent,
              onPress: () => onTap(item, item.poster?.url()),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 72,
                    child: PosterHero(
                      tag: posterHeroTag(item.id),
                      borderRadius: theme.style.borderRadius.md,
                      child: MediaImage(
                        url: item.poster?.url(),
                        headers: item.poster?.headers ?? const {},
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.body.sm.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (metadata != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            metadata,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.body.xs.copyWith(
                              color: theme.colors.mutedForeground,
                            ),
                          ),
                        ],
                        if (!wide && progressBar != null) ...[
                          const SizedBox(height: 8),
                          progressBar,
                        ],
                      ],
                    ),
                  ),
                  if (wide) ...[
                    SizedBox(width: gap),
                    SizedBox(width: 144, child: progressBar),
                  ],
                  SizedBox(width: gap),
                  SizedBox(
                    key: ValueKey('library-list-rating-${item.id}'),
                    width: MediaQuery.textScalerOf(context).scale(32),
                    child: rating != null && rating.isFinite && rating > 0
                        ? Text(
                            rating.toStringAsFixed(1),
                            textAlign: TextAlign.end,
                            style: theme.typography.body.sm.copyWith(
                              color: const Color(0xFFE2BB6A),
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    key: ValueKey('library-list-status-${item.id}'),
                    width: 18,
                    child: item.played
                        ? Icon(
                            FLucideIcons.circleCheck,
                            size: 18,
                            color: theme.colors.mutedForeground,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
