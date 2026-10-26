import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../shared/localization.dart';
import '../../shared/responsive_button.dart';
import '../../shared/widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PageContent(
      children: [
        PageHeading(l.home, hideTitleOnMobile: true),
        EmptyNotice(
          l.noServer,
          child: FButton(
            builder: responsiveButtonContent,
            mainAxisSize: MainAxisSize.min,
            onPress: () => context.go('/settings'),
            child: Text(l.settings),
          ),
        ),
      ],
    );
  }
}
