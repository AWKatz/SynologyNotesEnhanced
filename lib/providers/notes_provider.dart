import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import 'app_mode_provider.dart';
import 'notebooks_provider.dart';

final notesProvider = FutureProvider<List<Note>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  final notebookId = ref.watch(selectedNotebookIdProvider);
  return repo.listNotes(notebookId: notebookId);
});

final selectedNoteIdProvider = StateProvider<String?>((ref) => null);

final selectedNoteProvider = FutureProvider<Note?>((ref) async {
  final id = ref.watch(selectedNoteIdProvider);
  if (id == null) return null;
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return null;
  return repo.getNote(id);
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(notesProvider).valueOrNull ?? [];
  final query = ref.watch(searchQueryProvider).toLowerCase();

  var filtered = notes;
  if (query.isNotEmpty) {
    filtered = notes
        .where((n) =>
            n.title.toLowerCase().contains(query) ||
            n.displayExcerpt.toLowerCase().contains(query) ||
            n.tags.any((t) => t.toLowerCase().contains(query)))
        .toList();
  }

  filtered.sort((a, b) {
    if (a.isPinned && !b.isPinned) return -1;
    if (!a.isPinned && b.isPinned) return 1;
    final at = a.updatedAt ?? a.createdAt;
    final bt = b.updatedAt ?? b.createdAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });

  return filtered;
});

final allNotesCountProvider = Provider<int>((ref) {
  return ref.watch(notesProvider).valueOrNull?.length ?? 0;
});
