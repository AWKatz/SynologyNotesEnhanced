import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import 'app_mode_provider.dart';
import 'notebooks_provider.dart';
import 'shelves_provider.dart';
import 'tags_provider.dart';

/// Virtual, client-side-only nav views (Favorites / Locked notes) — not
/// backed by a dedicated repository query, so selecting one simply widens
/// the fetch to all notes and [filteredNotesProvider] narrows it further.
enum NoteFilter { favorites, locked }

final noteFilterProvider = StateProvider<NoteFilter?>((ref) => null);

enum NoteSortField { updated, title }

/// (field, ascending). Pinned notes always sort first regardless of this —
/// see [filteredNotesProvider] — this only controls the secondary key.
final noteSortProvider = StateProvider<(NoteSortField, bool)>(
    (ref) => (NoteSortField.updated, false));

final notesProvider = FutureProvider<List<Note>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  // A filter view (Favorites/Locked) is global, like the reference
  // screenshots' nav items — ignore whatever notebook happens to be selected.
  final notebookId = ref.watch(noteFilterProvider) == null
      ? ref.watch(selectedNotebookIdProvider)
      : null;
  return repo.listNotes(notebookId: notebookId);
});

/// Always all notes, regardless of the currently selected notebook/filter —
/// used for sidebar badge counts (All Notes / Favorites / Locked), which
/// must stay accurate even while a specific notebook is being browsed.
final allNotesGlobalProvider = FutureProvider<List<Note>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listNotes(notebookId: null);
});

final selectedNoteIdProvider = StateProvider<String?>((ref) => null);

/// True while the note editor is in rich-edit mode for the currently open
/// note — set by [_NoteEditorContentState], watched by the "new note" FAB so
/// it can hide itself instead of floating over the editor toolbar/content.
final noteEditingProvider = StateProvider<bool>((ref) => false);

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
final searchResultsProvider =
    FutureProvider.autoDispose<List<Note>>((ref) async {
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

  final noteFilter = ref.watch(noteFilterProvider);
  var filtered = notes;
  if (noteFilter == NoteFilter.favorites) {
    filtered = filtered.where((n) => n.isFavorite).toList();
  } else if (noteFilter == NoteFilter.locked) {
    filtered = filtered.where((n) => n.isEncrypted).toList();
  }

  final (sortField, ascending) = ref.watch(noteSortProvider);
  filtered.sort((a, b) {
    if (a.isPinned && !b.isPinned) return -1;
    if (!a.isPinned && b.isPinned) return 1;

    if (sortField == NoteSortField.title) {
      final cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return ascending ? cmp : -cmp;
    }

    // Date: notes with an unknown date always sort last, in either direction.
    final at = a.updatedAt ?? a.createdAt;
    final bt = b.updatedAt ?? b.createdAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    final cmp = at.compareTo(bt); // ascending = oldest first
    return ascending ? cmp : -cmp; // default (descending) = newest first
  });

  return filtered;
});

final allNotesCountProvider = Provider<int>((ref) {
  return ref.watch(allNotesGlobalProvider).valueOrNull?.length ?? 0;
});

/// Refreshes every provider a mutating action (save, create/delete note or
/// notebook, favorite/tag/encrypt) could have made stale — the same full set
/// the sidebar's manual sync button triggers. Call this after any such
/// action succeeds instead of hand-picking which providers to invalidate:
/// picking wrong (or forgetting one, e.g. favoriting a note not updating the
/// sidebar's Favorites count because only `notesProvider` was invalidated,
/// not `allNotesGlobalProvider`) is exactly why the app used to look "out of
/// sync" until the user tapped Sync themselves.
void syncAfterMutation(WidgetRef ref) {
  ref.invalidate(notebooksProvider);
  ref.invalidate(shelvesProvider);
  ref.invalidate(notesProvider);
  ref.invalidate(allNotesGlobalProvider);
  ref.invalidate(tagsProvider);
  ref.invalidate(selectedNoteProvider);
}
