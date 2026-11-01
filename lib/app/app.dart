import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

import '../core/settings/settings.dart';
import '../l10n/generated/app_localizations.dart';
import 'mouse_back_navigation.dart';
import 'router.dart';
import 'text_scaler.dart';
import 'theme.dart';

class SakugaApp extends ConsumerWidget {
  const SakugaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final (:light, :dark) = ref.watch(appThemesProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...FLocalizations.localizationsDelegates,
      ],
      themeMode: settings.themeMode,
      theme: light.toApproximateMaterialTheme(),
      darkTheme: dark.toApproximateMaterialTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: AppTextScaler(
            MediaQuery.textScalerOf(context),
            resolveFontScale(
              settings.fontScale,
              MediaQuery.devicePixelRatioOf(context),
            ),
          ),
        ),
        child: FTheme(
          data: Theme.brightnessOf(context) == Brightness.dark ? dark : light,
          child: MouseBackNavigation(
            onBack: router.routerDelegate.popRoute,
            child: FToaster(child: FTooltipGroup(child: child!)),
          ),
        ),
      ),
    );
  }
}
