import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/media_server/media_models.dart';
import '../library/library_providers.dart';

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<MediaItem>, String>((ref, term) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.search(library.userId, term);
    });
