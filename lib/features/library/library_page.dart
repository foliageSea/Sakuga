import 'dart:async';
import 'dart:math' as math;

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
  JellyfinItem? _series;

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
                onPress: () {
                  setState(() => _series = null);
                  ref.invalidate(libraryViewsProvider);
                },
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
    if (_series != null || notification.metrics.extentAfter > 480) return false;
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
    final view = library.viewById(viewId);
    final series = _series;
    if (series != null) {
      return [
        SliverToBoxAdapter(
          child: _SeriesHeader(
            series: series,
            onBack: () => setState(() => _series = null),
          ),
        ),
        _SeriesView(
          client: library.client,
          userId: library.userId,
          series: series,
        ),
      ];
    }
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
                  onPress: () => setState(() {
                    _selectedViewId = view.id;
                    _series = null;
                  }),
                  child: Text(view.name),
                ),
            ],
          ),
        ),
      ),
      _PagedGrid(
        client: library.client,
        query: (userId: library.userId, viewId: viewId),
        onTap: view != null && view.isTvShows
            ? (item) => setState(() => _series = item)
            : null,
      ),
    ];
  }
}

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({required this.series, required this.onBack});

  final JellyfinItem series;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          FButton.icon(
            variant: .outline,
            size: .sm,
            semanticsLabel: l.back,
            onPress: onBack,
            child: const Icon(FLucideIcons.arrowLeft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              series.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.theme.typography.body.lg.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PagedGrid extends ConsumerWidget {
  const _PagedGrid({required this.client, required this.query, this.onTap});

  final JellyfinClient client;
  final LibraryQuery query;
  final ValueChanged<JellyfinItem>? onTap;

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
                      ? _PosterCard(
                          client: client,
                          item: state.items[start + column],
                          onTap: onTap == null
                              ? null
                              : () => onTap!(state.items[start + column]),
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

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.client, required this.item, this.onTap});

  final JellyfinClient client;
  final JellyfinItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Surface(
        padding: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(200, 1200);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: context.theme.style.borderRadius.md,
                    child: _PosterImage(
                      client: client,
                      url: client.imageUrl(item, width: width),
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
            );
          },
        ),
      ),
    );
  }
}

class _SeriesView extends ConsumerStatefulWidget {
  const _SeriesView({
    required this.client,
    required this.userId,
    required this.series,
  });

  final JellyfinClient client;
  final String userId;
  final JellyfinItem series;

  @override
  ConsumerState<_SeriesView> createState() => _SeriesViewState();
}

class _SeriesViewState extends ConsumerState<_SeriesView> {
  String? _seasonId;

  @override
  Widget build(BuildContext context) {
    final seasons = ref.watch(
      seriesSeasonsProvider((
        userId: widget.userId,
        seriesId: widget.series.id,
      )),
    );
    final episodesQuery = (
      userId: widget.userId,
      seriesId: widget.series.id,
      seasonId: _seasonId,
    );
    final episodes = ref.watch(seriesEpisodesProvider(episodesQuery));
    return SliverMainAxisGroup(
      slivers: [
        ...seasons.when(
          data: (values) => values.length <= 1
              ? const <Widget>[]
              : <Widget>[_seasonChips(context, values)],
          loading: () => const <Widget>[],
          error: (_, _) => const <Widget>[],
        ),
        ...episodes.when(
          data: (values) => _episodeSlivers(context, values),
          loading: () => [const SliverToBoxAdapter(child: LoadingNotice())],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: ErrorNotice(
                error,
                onRetry: () =>
                    ref.invalidate(seriesEpisodesProvider(episodesQuery)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _seasonChips(BuildContext context, List<JellyfinItem> seasons) {
    final l = context.l10n;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              context,
              label: l.all,
              selected: _seasonId == null,
              onPress: () => setState(() => _seasonId = null),
            ),
            for (final season in seasons)
              _chip(
                context,
                label: season.name,
                selected: _seasonId == season.id,
                onPress: () => setState(() => _seasonId = season.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onPress,
  }) => FButton(
    builder: responsiveButtonContent,
    mainAxisSize: MainAxisSize.min,
    variant: selected ? .primary : .outline,
    onPress: onPress,
    child: Text(label),
  );

  List<Widget> _episodeSlivers(
    BuildContext context,
    List<JellyfinItem> episodes,
  ) {
    if (episodes.isEmpty) {
      return [SliverToBoxAdapter(child: EmptyNotice(context.l10n.noItems))];
    }
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _EpisodeTile(client: widget.client, item: episodes[index]),
          ),
          childCount: episodes.length,
        ),
      ),
    ];
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.client, required this.item});

  final JellyfinClient client;
  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final code = item.episodeCode;
    return Surface(
      padding: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: AspectRatio(
              aspectRatio: item.thumbnailAspectRatio,
              child: ClipRRect(
                borderRadius: theme.style.borderRadius.md,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width =
                        (constraints.maxWidth *
                                MediaQuery.devicePixelRatioOf(context))
                            .round()
                            .clamp(200, 800);
                    return _PosterImage(
                      client: client,
                      url: client.imageUrl(item, width: width),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.md,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (code != null)
                      Text(
                        code,
                        style: theme.typography.body.sm.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    if (code != null && item.played) const SizedBox(width: 8),
                    if (item.played)
                      Icon(
                        FLucideIcons.check,
                        size: 14,
                        color: theme.colors.mutedForeground,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.client, required this.url});

  final JellyfinClient client;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null) return const _Placeholder(icon: FLucideIcons.film);
    return Stack(
      fit: StackFit.expand,
      children: [
        const _Placeholder(icon: FLucideIcons.film),
        Image.network(
          url,
          headers: client.authHeaders,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ],
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
