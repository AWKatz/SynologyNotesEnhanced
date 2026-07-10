import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/tag.dart';
import 'app_mode_provider.dart';

final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listTags();
});

final tagNameMapProvider = Provider<Map<String, String>>((ref) {
  final tags = ref.watch(tagsProvider).valueOrNull ?? [];
  return {for (final t in tags) t.id: t.name};
});
