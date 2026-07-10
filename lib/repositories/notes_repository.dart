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
}
