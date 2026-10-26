import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/jellyfin/jellyfin_models.dart';
import '../library/library_providers.dart';

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<JellyfinItem>, String>((ref, term) async {
      final library = await ref.watch(libraryViewsProvider.future);
      return library.client.search(library.userId, term);
    });
