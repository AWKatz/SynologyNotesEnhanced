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

/// Inverts Tag.noteIds into noteId -> [tagId]. `Note.list` doesn't return
/// per-note tags (only `Note.get` does), so this is how the note list/search
/// learns which notes have which tags without fetching each one individually.
final noteTagsProvider = Provider<Map<String, List<String>>>((ref) {
  final tags = ref.watch(tagsProvider).valueOrNull ?? [];
  final map = <String, List<String>>{};
  for (final tag in tags) {
    for (final noteId in tag.noteIds) {
      (map[noteId] ??= []).add(tag.id);
    }
  }
  return map;
});
