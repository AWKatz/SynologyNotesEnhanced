import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notes_provider.dart';
import 'notebooks_provider.dart';
import 'tags_provider.dart';

final starredNotesCountProvider = Provider<int>((ref) {
  final notes = ref.watch(notesProvider).valueOrNull ?? [];
  return notes.where((n) => n.isFavorite).length;
});

final userNotebooksCountProvider = Provider<int>((ref) {
  final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
  return notebooks.where((n) => !n.isShared).length;
});

final sharedNotebooksCountProvider = Provider<int>((ref) {
  final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
  return notebooks.where((n) => n.isShared).length;
});

final tagsCountProvider = Provider<int>((ref) {
  final tags = ref.watch(tagsProvider).valueOrNull ?? [];
  return tags.length;
});

// Stubbed until the Todo model and API are wired up in a future phase.
final todosCountProvider = Provider<int>((ref) => 0);
