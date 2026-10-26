import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../data/jellyfin/jellyfin_client.dart';
import '../../shared/localization.dart';
import '../../shared/media_widgets.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';
import '../library/library_providers.dart';
import 'search_providers.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const _debounceDelay = Duration(milliseconds: 300);

  final _controller = TextEditingController();
  Timer? _debounce;
  String _term = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scheduleSearch);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    final term = _controller.text.trim();
    _debounce?.cancel();
    if (term == _term) return;
    _debounce = Timer(_debounceDelay, () {
      if (!mounted) return;
      setState(() => _term = term);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final server = ref.watch(activeServerProvider);
    if (server == null) {
      return PageContent(
        children: [
          PageHeading(l.search, hideTitleOnMobile: true),
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
          PageHeading(l.search, hideTitleOnMobile: true),
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

    final library = ref.watch(libraryViewsProvider);
    return PageContent(
      children: [
        PageHeading(l.search, hideTitleOnMobile: true),
        FTextField(
          control: .managed(controller: _controller),
          hint: l.searchHint,
        ),
        const SizedBox(height: 20),
        if (_term.isEmpty)
          EmptyNotice(l.emptySearch)
        else
          ...library.when(
            data: (data) => [_SearchResults(client: data.client, term: _term)],
            loading: () => const [LoadingNotice()],
            error: (error, _) => [
              ErrorNotice(
                error,
                onRetry: () => ref.invalidate(libraryViewsProvider),
              ),
            ],
          ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.client, required this.term});

  final JellyfinClient client;
  final String term;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider(term));
    return results.when(
      data: (items) => items.isEmpty
          ? EmptyNotice(context.l10n.noResults)
          : AdaptiveGrid(
              minWidth: 160,
              maxColumns: 6,
              children: [
                for (final item in items)
                  MediaPosterCard(
                    client: client,
                    item: item,
                    progress: item.progressFraction,
                    onTap: () => context.go('/library/${item.id}'),
                  ),
              ],
            ),
      loading: () => const LoadingNotice(),
      error: (error, _) => ErrorNotice(
        error,
        onRetry: () => ref.invalidate(searchResultsProvider(term)),
      ),
    );
  }
}
