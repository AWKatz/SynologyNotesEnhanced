import '../models/note.dart';
import '../models/note_version.dart';
import '../models/notebook.dart';
import '../models/shelf.dart';
import '../models/smart_notebook.dart';
import '../models/tag.dart';
import '../models/todo.dart';

abstract class NotesRepository {
  Future<List<Shelf>> listShelves();
  Future<List<Notebook>> listNotebooks();
  Future<Notebook> createNotebook({required String title, String? shelfId});
  Future<void> deleteNotebook(String notebookId);
  Future<Notebook> renameNotebook(
      {required String notebookId, required String title});
  Future<List<Note>> listNotes({String? notebookId});
  Future<Note> getNote(String noteId, {String? ver});
  Future<Note> createNote({
    required String notebookId,
    required String title,
    String content = '',
    List<String> tagIds = const [],
  });
  Future<Note> updateNote({
    required String noteId,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isStarred,
    String? notebookId,
  });
  Future<void> deleteNote(String noteId);
  /// Permanently deletes an already-trashed note — see
  /// NoteStationService.purgeNote's doc comment.
  Future<void> purgeNote(String noteId);
  /// Restores a trashed note to its original notebook.
  Future<void> restoreNote(String noteId);
  Future<List<Note>> listTrashedNotes();
  Future<List<Tag>> listTags();
  Future<Tag> createTag(String name);
  Future<List<Note>> search({required String keyword});

  /// Encrypts a currently-plain [note] with [password]. NAS mode: creates a
  /// new note carrying the encrypted content and trashes the plaintext
  /// original (see NasNotesRepository — mirrors the verified Note.copy wire
  /// format, but never leaves the stock client's plaintext-duplicate behind).
  /// Local mode: rewrites the note in place.
  Future<Note> encryptNote({required Note note, required String password});

  /// Uploads an image attachment while saving [content] (which must already
  /// embed the matching `<img ref="$ref">` tag) — see
  /// NoteStationService.uploadNoteAttachment for the verified wire format.
  /// NAS-only: offline/local mode has no attachment storage, matching how
  /// rich-editor saves are already NAS-only (see note_editor.dart).
  Future<Note> uploadNoteAttachment({
    required Note note,
    required String content,
    required String fileName,
    required List<int> fileBytes,
    required String ref,
  });

  // ── Version history (NAS-only — see LocalNotesRepository) ────────────────
  Future<List<NoteVersion>> listNoteVersions(String noteId);
  Future<Note> restoreNoteVersion({required String noteId, required String ver});

  // ── Todo (NAS-only — see LocalNotesRepository) ───────────────────────────
  // [parentId] on either method scopes to/creates a subtask.
  Future<List<Todo>> listTodos({String? parentId});
  Future<Todo> createTodo(
      {required String title, DateTime? dueDate, String? parentId});
  Future<void> updateTodo({
    required String todoId,
    String? title,
    String? comment,
    bool? done,
    bool? star,
    int? priority,
    DateTime? dueDate,
  });
  Future<void> deleteTodo(String todoId);

  // ── Smart notebooks (NAS-only) ───────────────────────────────────────────
  Future<List<SmartNotebook>> listSmartNotebooks();
  Future<SmartNotebook> createSmartNotebook({
    required String title,
    required SmartCriteria criteria,
  });
  /// Notes matching [smartId]'s saved query — computed server-side, see
  /// NoteStationService.listNotesInSmart's doc comment.
  Future<List<Note>> listNotesForSmart(String smartId);

  // ── Sharing / Permissions (NAS-only) ─────────────────────────────────────
  Future<String> getPublicShareLink(String noteId);
  Future<void> setSharingEnabled(String noteId, bool enabled);
  Future<void> setPublicPermission(String noteId, String perm);
  Future<void> deletePublicPermission(String noteId);
  Future<void> setGroupPermission({
    required String noteId,
    required String groupName,
    required String perm,
  });
  Future<void> setUserPermission({
    required String noteId,
    required String username,
    required String perm,
  });
  Future<void> deleteUserPermission({
    required String noteId,
    required String username,
    required String uid,
  });
  /// UNVERIFIED — see NoteStationService.deleteGroupPermission's doc comment.
  Future<void> deleteGroupPermission({
    required String noteId,
    required String groupName,
    required String gid,
  });
  Future<List<({String name, String type})>> searchSharePriv(String query);

  // ── Server-side .nsx export/import job (NAS-only) — see
  // NoteStationService's matching doc comment for how this differs from the
  // app's own local NsxCodec/NsxService.
  Future<String> startNotebookExport({
    String? notebookId,
    required String destPath,
    bool exportTodo = true,
  });
  Future<({bool finished, int current, int total})> getNotebookExportStatus();
  Future<String> startNotebookImport({
    required String fileName,
    required String nasPath,
  });
  Future<({bool finished, int current, int total})> getNotebookImportStatus();
}
