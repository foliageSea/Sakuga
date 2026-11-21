import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import 'library_providers.dart';

class LibraryFilterPanel extends ConsumerStatefulWidget {
  const LibraryFilterPanel({
    required this.query,
    required this.showAdvancedFilters,
    required this.onGenre,
    required this.onPlayed,
    required this.onYear,
    super.key,
  });
  final LibraryQuery query;
  final bool showAdvancedFilters;
  final ValueChanged<String?> onGenre;
  final ValueChanged<bool?> onPlayed;
  final ValueChanged<int?> onYear;

  @override
  ConsumerState<LibraryFilterPanel> createState() => _LibraryFilterPanelState();
}

class _LibraryFilterPanelState extends ConsumerState<LibraryFilterPanel> {
  bool _allYears = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final query = (userId: widget.query.userId, viewId: widget.query.viewId);
    final genres = ref.watch(libraryGenresProvider(query));
    final years = widget.showAdvancedFilters
        ? ref.watch(libraryYearsProvider(query))
        : const AsyncData<List<int>>([]);
    final yearOptions = {...?years.value, ?widget.query.year}.toList()
      ..sort((a, b) => b.compareTo(a));
    return Container(
      key: const ValueKey('library-filter-panel'),
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.theme.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showAdvancedFilters) ...[
            _FilterRow<bool>(
              id: 'progress',
              label: l.libraryProgress,
              selected: widget.query.isPlayed,
              options: {false: l.libraryUnwatched, true: l.libraryWatched},
              onSelect: widget.onPlayed,
            ),
            const SizedBox(height: 6),
          ],
          _FilterRow<String>(
            id: 'genre',
            label: l.genre,
            selected: widget.query.genre,
            options: {
              for (final genre in {...?genres.value, ?widget.query.genre})
                if (genre.isNotEmpty) genre: genre,
            },
            onSelect: widget.onGenre,
            trailing: genres.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: FCircularProgress(),
                  )
                : genres.hasError
                ? FButton(
                    key: const ValueKey('library-genres-retry'),
                    variant: .ghost,
                    mainAxisSize: MainAxisSize.min,
                    builder: responsiveButtonContent,
                    onPress: () => ref.invalidate(libraryGenresProvider(query)),
                    child: Text(l.genresLoadError),
                  )
                : null,
          ),
          if (widget.showAdvancedFilters) ...[
            const SizedBox(height: 6),
            _FilterRow<int>(
              id: 'year',
              label: l.libraryYear,
              selected: widget.query.year,
              options: {
                for (final year
                    in _allYears
                        ? yearOptions
                        : {...yearOptions.take(8), ?widget.query.year})
                  year: '$year',
              },
              onSelect: widget.onYear,
              trailing: years.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: FCircularProgress(),
                    )
                  : years.hasError
                  ? FButton(
                      key: const ValueKey('library-years-retry'),
                      variant: .ghost,
                      mainAxisSize: MainAxisSize.min,
                      builder: responsiveButtonContent,
                      onPress: () =>
                          ref.invalidate(libraryYearsProvider(query)),
                      child: Text(l.libraryYearsLoadError),
                    )
                  : yearOptions.length > 8
                  ? FButton(
                      variant: .ghost,
                      size: .sm,
                      mainAxisSize: MainAxisSize.min,
                      builder: responsiveButtonContent,
                      onPress: () => setState(() => _allYears = !_allYears),
                      child: Text(
                        _allYears ? l.libraryFewerYears : l.libraryMoreYears,
                      ),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterRow<T> extends StatelessWidget {
  const _FilterRow({
    required this.id,
    required this.label,
    required this.selected,
    required this.options,
    required this.onSelect,
    this.trailing,
  });
  final String id;
  final String label;
  final T? selected;
  final Map<T, String> options;
  final ValueChanged<T?> onSelect;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    Widget choice(T? value, String text) => Semantics(
      selected: selected == value,
      child: FButton(
        key: ValueKey('library-$id-${value ?? 'all'}'),
        variant: .ghost,
        size: .sm,
        mainAxisSize: MainAxisSize.min,
        builder: responsiveButtonContent,
        onPress: () => onSelect(value),
        child: Text(
          text,
          style: theme.typography.body.sm.copyWith(
            color: selected == value
                ? theme.colors.primary
                : theme.colors.mutedForeground,
            fontWeight: selected == value ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
    return Row(
      key: ValueKey('library-$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(
              label,
              style: theme.typography.body.sm.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              choice(null, context.l10n.all),
              for (final entry in options.entries)
                choice(entry.key, entry.value),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}
