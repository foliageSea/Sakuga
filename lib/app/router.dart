import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:forui/forui.dart';

import '../features/detail/detail_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/player/player_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/localization.dart';
import '../shared/responsive_button.dart';
import 'branch_transition.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

const _devStartRoute = String.fromEnvironment('DEV_START_ROUTE');

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: _devStartRoute.isEmpty ? '/home' : _devStartRoute,
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: animatedBranchContainer,
        builder: (context, state, shell) => AppShell(
          shell: shell,
          isHomeRoute: state.fullPath == '/home',
          detailBackgroundSpec: _detailBackgroundSpec(state),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                pageBuilder: (_, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) =>
                          FadeTransition(
                            opacity: ReverseAnimation(
                              CurvedAnimation(
                                parent: secondaryAnimation,
                                curve: Curves.easeOutCubic,
                                reverseCurve: Curves.easeInCubic,
                              ),
                            ),
                            child: child,
                          ),
                  child: const LibraryPage(),
                ),
                routes: [
                  GoRoute(
                    path: ':itemId',
                    pageBuilder: (_, state) => buildDetailTransitionPage(state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/downloads',
                builder: (_, _) => const DownloadsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
      // A single route: the player must not stack a second player page under
      // the one that carries the item, so the item travels as a query.
      GoRoute(
        path: '/player',
        builder: (_, state) =>
            PlayerPage(itemId: state.uri.queryParameters['item']),
      ),
    ],
    errorBuilder: (context, _) => FScaffold(
      child: Center(
        child: FButton(
          builder: responsiveButtonContent,
          onPress: () => context.go('/home'),
          child: Text('${context.l10n.notFound} · ${context.l10n.goHome}'),
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

DetailBackgroundSpec? _detailBackgroundSpec(GoRouterState state) {
  if (state.fullPath != '/library/:itemId') return null;
  final itemId = state.pathParameters['itemId'];
  if (itemId == null || itemId.isEmpty) return null;
  final extra = state.extra is DetailRouteExtra
      ? state.extra as DetailRouteExtra
      : null;
  return (
    itemId: itemId,
    initialItem: extra?.item,
    initialPosterUrl: extra?.posterUrl,
  );
}
