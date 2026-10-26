import 'package:flutter/widgets.dart';

import '../../shared/localization.dart';
import '../../shared/widgets.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PageContent(
      children: [
        PageHeading(l.downloads, hideTitleOnMobile: true),
        EmptyNotice(l.emptyDownloads),
      ],
    );
  }
}
