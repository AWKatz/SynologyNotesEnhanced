import '../models/note.dart';
import '../models/notebook.dart';
import '../models/shelf.dart';
import '../models/tag.dart';

abstract class NotesRepository {
  Future<List<Shelf>> listShelves();
  Future<List<Notebook>> listNotebooks();
  Future<Notebook> createNotebook({required String title, String? shelfId});
  Future<void> deleteNotebook(String notebookId);
  Future<Notebook> renameNotebook({required String notebookId, required String title});
  Future<List<Note>> listNotes({String? notebookId});
  Future<Note> getNote(String noteId);
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
  });
  Future<void> deleteNote(String noteId);
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
}
