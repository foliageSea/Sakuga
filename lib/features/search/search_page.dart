import 'package:flutter/widgets.dart';

import '../../shared/localization.dart';
import '../../shared/widgets.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PageContent(
      children: [
        PageHeading(l.search, hideTitleOnMobile: true),
        EmptyNotice(l.emptySearch),
      ],
    );
  }
}
