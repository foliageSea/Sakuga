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
import '../library/library_providers.dart';
import '../player/player_route.dart';
import 'detail_providers.dart';

/// Seed data carried from a tapped poster card so the detail header and
/// poster [Hero] render on the first frame while full metadata loads.
class DetailRouteExtra {
  const DetailRouteExtra({required this.item, this.posterUrl});

  final JellyfinItem item;
  final String? posterUrl;
}

/// Builds a fade page for [DetailPage] so the poster [Hero] flies smoothly on
/// both push and pop without a competing slide or translate offset.
CustomTransitionPage<void> buildDetailTransitionPage(GoRouterState state) {
  final itemId = state.pathParameters['itemId'] ?? '';
  final extra = state.extra is DetailRouteExtra
      ? state.extra as DetailRouteExtra
      : null;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        ),
    child: DetailPage(
      itemId: itemId,
      initialItem: extra?.item,
      initialPosterUrl: extra?.posterUrl,
    ),
  );
}

class DetailPage extends ConsumerWidget {
  const DetailPage({
    required this.itemId,
    this.initialItem,
    this.initialPosterUrl,
    super.key,
  });

  final String itemId;
  final JellyfinItem? initialItem;
  final String? initialPosterUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryViewsProvider);
    final preview = initialItem?.id == itemId ? initialItem : null;
    return library.when(
      data: (data) => _DetailBody(
        client: data.client,
        userId: data.userId,
        itemId: itemId,
        initialItem: preview,
        initialPosterUrl: initialPosterUrl,
      ),
      loading: () {
        final server = ref.watch(activeServerProvider);
        if (server != null && preview != null) {
          return _DetailScaffold(
            slivers: [
              SliverToBoxAdapter(
                child: _Hero(
                  client: JellyfinClient(server: server),
                  item: preview,
                  posterUrl: initialPosterUrl,
                ),
              ),
              const SliverToBoxAdapter(child: LoadingNotice()),
            ],
          );
        }
        return const _DetailScaffold(
          slivers: [SliverToBoxAdapter(child: LoadingNotice())],
        );
      },
      error: (error, _) => _DetailScaffold(
        slivers: [
          SliverToBoxAdapter(
            child: ErrorNotice(
              error,
              onRetry: () => ref.invalidate(libraryViewsProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.client,
    required this.userId,
    required this.itemId,
    this.initialItem,
    this.initialPosterUrl,
  });

  final JellyfinClient client;
  final String userId;
  final String itemId;
  final JellyfinItem? initialItem;
  final String? initialPosterUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = (userId: userId, itemId: itemId);
    final item = ref.watch(libraryItemProvider(query));
    final preview = initialItem;
    return item.when(
      data: (value) {
        final reusePosterUrl =
            initialPosterUrl != null &&
            value.imageTags['Primary'] == preview?.imageTags['Primary'];
        return _DetailScaffold(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: value,
                posterUrl: reusePosterUrl ? initialPosterUrl : null,
              ),
            ),
            SliverToBoxAdapter(child: _About(item: value)),
            if (value.isSeries)
              _Episodes(client: client, userId: userId, series: value),
          ],
        );
      },
      loading: () => _DetailScaffold(
        slivers: [
          if (preview != null)
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: preview,
                posterUrl: initialPosterUrl,
              ),
            ),
          const SliverToBoxAdapter(child: LoadingNotice()),
        ],
      ),
      error: (error, _) => _DetailScaffold(
        slivers: [
          if (preview != null)
            SliverToBoxAdapter(
              child: _Hero(
                client: client,
                item: preview,
                posterUrl: initialPosterUrl,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: preview == null ? 0 : 24),
              child: ErrorNotice(
                error,
                onRetry: () => ref.invalidate(libraryItemProvider(query)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The detail page shell: the back bar is pinned above the scrolling content
/// so it stays reachable in every state, including loading and errors.
class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.slivers});

  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => PageScrollView(
    header: const _BackBar(),
    animate: false,
    slivers: slivers,
  );
}

class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Row(
      children: [
        FButton.icon(
          key: const ValueKey('detail-back'),
          variant: .outline,
          size: .sm,
          semanticsLabel: l.back,
          onPress: () => _goBack(context),
          child: const Icon(FLucideIcons.arrowLeft),
        ),
      ],
    );
  }
}

/// Pops the detail route, falling back to the library when the page was opened
/// directly, e.g. from a deep link.
void _goBack(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/library');
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.client, required this.item, this.posterUrl});

  final JellyfinClient client;
  final JellyfinItem item;
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final mobile = isMobileLayout(context);
    final available =
        math.min(MediaQuery.sizeOf(context).width, 1440) -
        pagePadding(context) * 2;
    final posterWidth = mobile ? 96.0 : 132.0;
    final poster = AspectRatio(
      aspectRatio: 2 / 3,
      child: PosterHero(
        tag: posterHeroTag(item.id),
        borderRadius: theme.style.borderRadius.md,
        child: MediaImage(
          url:
              posterUrl ??
              client.imageUrl(
                item,
                width: (posterWidth * ratio * 2).round().clamp(200, 800),
              ),
          headers: client.authHeaders,
        ),
      ),
    );
    final backdrop = MediaImage(
      url: client.backdropUrl(
        item,
        width: (available * ratio).round().clamp(320, 2400),
      ),
      headers: client.authHeaders,
    );
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: theme.style.borderRadius.lg,
            child: AspectRatio(aspectRatio: 16 / 9, child: backdrop),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: posterWidth, child: poster),
              const SizedBox(width: 12),
              Expanded(child: _TitleBlock(item: item, onDark: false)),
            ],
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: theme.style.borderRadius.lg,
      child: SizedBox(
        height: 340,
        child: Stack(
          fit: StackFit.expand,
          children: [
            backdrop,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1A000000), Color(0xF2000000)],
                  stops: [0.25, 1],
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(width: posterWidth, child: poster),
                  const SizedBox(width: 20),
                  Expanded(child: _TitleBlock(item: item, onDark: true)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.item, required this.onDark});

  final JellyfinItem item;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final foreground = onDark
        ? const Color(0xFFFFFFFF)
        : theme.colors.foreground;
    final muted = onDark
        ? const Color(0xCCFFFFFF)
        : theme.colors.mutedForeground;
    final background = onDark ? const Color(0x33FFFFFF) : theme.colors.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.display.xl.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (item.productionYear != null)
              _Tag(
                text: '${item.productionYear}',
                foreground: muted,
                background: background,
              ),
            if (item.officialRating != null)
              _Tag(
                text: item.officialRating!,
                foreground: muted,
                background: background,
              ),
            for (final genre in item.genres.take(3))
              _Tag(text: genre, foreground: muted, background: background),
          ],
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.foreground,
    required this.background,
  });

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: context.theme.typography.body.xs.copyWith(color: foreground),
    ),
  );
}

class _About extends StatelessWidget {
  const _About({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = context.theme;
    final overview = item.overview?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overview.isNotEmpty) ...[
            _SectionTitle(l.synopsis),
            const SizedBox(height: 8),
            Text(overview, style: theme.typography.body.sm),
          ],
          if (item.people.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle(l.cast),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in item.people.take(12))
                  _PersonChip(person: person),
              ],
            ),
          ],
          if (item.studios.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionTitle(l.studios),
            const SizedBox(height: 8),
            Text(
              item.studios.join(' · '),
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.theme.typography.body.lg.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person});

  final JellyfinPerson person;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colors.muted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(person.name, style: theme.typography.body.sm),
          if (person.role.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              person.role,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Episodes extends ConsumerStatefulWidget {
  const _Episodes({
    required this.client,
    required this.userId,
    required this.series,
  });

  final JellyfinClient client;
  final String userId;
  final JellyfinItem series;

  @override
  ConsumerState<_Episodes> createState() => _EpisodesState();
}

class _EpisodesState extends ConsumerState<_Episodes> {
  String? _seasonId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final seasons = ref.watch(
      seriesSeasonsProvider((
        userId: widget.userId,
        seriesId: widget.series.id,
      )),
    );
    final query = (
      userId: widget.userId,
      seriesId: widget.series.id,
      seasonId: _seasonId,
    );
    final episodes = ref.watch(seriesEpisodesProvider(query));
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 12),
            child: _SectionTitle(l.episodes),
          ),
        ),
        ...seasons.when(
          data: (values) => values.length <= 1
              ? const <Widget>[]
              : <Widget>[
                  SliverToBoxAdapter(child: _seasonChips(context, values)),
                ],
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
                onRetry: () => ref.invalidate(seriesEpisodesProvider(query)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _seasonChips(BuildContext context, List<JellyfinItem> seasons) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push(playerLocation(item.id)),
      child: Surface(
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
                      return MediaImage(
                        url: client.imageUrl(item, width: width),
                        headers: client.authHeaders,
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
      ),
    );
  }
}
