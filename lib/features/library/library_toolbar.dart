import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../data/media_server/media_models.dart';
import '../../shared/localization.dart';

class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    required this.filtersVisible,
    required this.hasFilters,
    required this.listView,
    required this.sort,
    required this.descending,
    required this.onToggleFilters,
    required this.onView,
    required this.onSort,
    required this.onClear,
    this.showLibraryOptions = true,
    super.key,
  });
  final bool filtersVisible;
  final bool hasFilters;
  final bool listView;
  final MediaSort sort;
  final bool descending;
  final VoidCallback onToggleFilters;
  final ValueChanged<bool> onView;
  final void Function(MediaSort, bool) onSort;
  final VoidCallback onClear;
  final bool showLibraryOptions;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final choices = <(MediaSort, String)>[
      (MediaSort.name, l.librarySortName),
      (MediaSort.dateAdded, l.librarySortNewest),
      (MediaSort.year, l.librarySortYear),
      (MediaSort.rating, l.librarySortRating),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLibraryOptions) ...[
          if (hasFilters) ...[
            FButton.icon(
              key: const ValueKey('library-clear-filters'),
              variant: .ghost,
              size: .sm,
              semanticsLabel: l.clearFilters,
              onPress: onClear,
              child: const Icon(FLucideIcons.filterX),
            ),
            const SizedBox(width: 4),
          ],
          FButton.icon(
            key: const ValueKey('library-toggle-filters'),
            variant: .outline,
            size: .sm,
            selected: filtersVisible,
            semanticsLabel: l.libraryFilters,
            onPress: onToggleFilters,
            child: Icon(
              FLucideIcons.listFilter,
              color: filtersVisible || hasFilters
                  ? context.theme.colors.primary
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          FPopoverMenu(
            menuAnchor: .topRight,
            childAnchor: .bottomRight,
            menuBuilder: (context, controller, _) => [
              FItemGroup(
                children: [
                  for (final (value, label) in choices)
                    FItem(
                      key: ValueKey('library-sort-${value.name}'),
                      title: Text(label),
                      selected: sort == value,
                      suffix: sort == value
                          ? const Icon(FLucideIcons.check, size: 16)
                          : null,
                      onPress: () {
                        controller.hide();
                        onSort(value, value != MediaSort.name);
                      },
                    ),
                ],
              ),
              FItemGroup(
                children: [
                  FItem(
                    key: const ValueKey('library-sort-ascending'),
                    title: Text(l.librarySortAscending),
                    selected: !descending,
                    suffix: !descending
                        ? const Icon(FLucideIcons.check, size: 16)
                        : null,
                    onPress: () {
                      controller.hide();
                      onSort(sort, false);
                    },
                  ),
                  FItem(
                    key: const ValueKey('library-sort-descending'),
                    title: Text(l.librarySortDescending),
                    selected: descending,
                    suffix: descending
                        ? const Icon(FLucideIcons.check, size: 16)
                        : null,
                    onPress: () {
                      controller.hide();
                      onSort(sort, true);
                    },
                  ),
                ],
              ),
            ],
            builder: (context, controller, _) => FButton.icon(
              key: const ValueKey('library-sort'),
              variant: .outline,
              size: .sm,
              semanticsLabel: l.librarySort,
              onPress: controller.toggle,
              child: const Icon(FLucideIcons.arrowDownWideNarrow),
            ),
          ),
          const SizedBox(width: 8),
        ],
        FButton.icon(
          key: const ValueKey('library-grid-view'),
          variant: listView ? .ghost : .secondary,
          size: .sm,
          selected: !listView,
          semanticsLabel: l.libraryGridView,
          onPress: () => onView(false),
          child: const Icon(FLucideIcons.layoutGrid),
        ),
        const SizedBox(width: 2),
        FButton.icon(
          key: const ValueKey('library-list-view'),
          variant: listView ? .secondary : .ghost,
          size: .sm,
          selected: listView,
          semanticsLabel: l.libraryListView,
          onPress: () => onView(true),
          child: const Icon(FLucideIcons.list),
        ),
      ],
    );
  }
}
