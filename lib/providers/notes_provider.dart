import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import 'app_mode_provider.dart';
import 'notebooks_provider.dart';
import 'tags_provider.dart';

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

/// Real server-side full-text search (`SYNO.NoteStation.FTS` / the local
/// repo's own search) rather than substring-filtering the already-loaded
/// page. Debounced so fast typing doesn't fire a request per keystroke;
/// `ref.mounted` after the delay drops the result if a newer query already
/// superseded this one.
final searchResultsProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) return const [];
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const [];
  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future.delayed(const Duration(milliseconds: 300));
  if (disposed) return const [];
  return repo.search(keyword: query);
});

final filteredNotesProvider = Provider<List<Note>>((ref) {
  final query = ref.watch(searchQueryProvider).trim();
  final noteTags = ref.watch(noteTagsProvider);

  List<Note> notes;
  if (query.isEmpty) {
    notes = ref.watch(notesProvider).valueOrNull ?? [];
  } else {
    notes = ref.watch(searchResultsProvider).valueOrNull ?? [];
    // search() has no notebook scope; narrow to the notebook being browsed
    // (if any) so searching still respects "All Notes" vs. a specific one.
    final notebookId = ref.watch(selectedNotebookIdProvider);
    if (notebookId != null) {
      notes = notes.where((n) => n.notebookId == notebookId).toList();
    }
  }

  // Note.list never returns per-note tags (only Note.get does) — fill them
  // in from the Tag.list-derived reverse index so list/search see real tags.
  notes = notes.map((n) {
    if (n.tags.isNotEmpty) return n;
    final tags = noteTags[n.id];
    return tags == null ? n : n.copyWith(tags: tags);
  }).toList();

  final filtered = notes;
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
