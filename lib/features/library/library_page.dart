import 'package:flutter/widgets.dart';

import '../../shared/localization.dart';
import '../../shared/widgets.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PageContent(
      children: [
        PageHeading(l.library, hideTitleOnMobile: true),
        EmptyNotice(l.emptyLibrary),
      ],
    );
  }
}
