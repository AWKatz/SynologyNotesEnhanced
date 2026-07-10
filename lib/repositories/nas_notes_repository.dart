import '../core/services/note_station_service.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../models/shelf.dart';
import '../models/tag.dart';
import 'notes_repository.dart';

class NasNotesRepository implements NotesRepository {
  final NoteStationService _service;
  const NasNotesRepository(this._service);

  @override
  Future<List<Shelf>> listShelves() => _service.listShelves();

  @override
  Future<List<Notebook>> listNotebooks() => _service.listNotebooks();

  @override
  Future<Notebook> createNotebook({required String title, String? shelfId}) =>
      _service.createNotebook(title: title, shelfId: shelfId);

  @override
  Future<void> deleteNotebook(String notebookId) =>
      _service.deleteNotebook(notebookId);

  @override
  Future<Notebook> renameNotebook({required String notebookId, required String title}) =>
      _service.renameNotebook(notebookId: notebookId, title: title);

  @override
  Future<List<Note>> listNotes({String? notebookId}) =>
      _service.listNotes(notebookId: notebookId);

  @override
  Future<Note> getNote(String noteId) => _service.getNote(noteId);

  @override
  Future<Note> createNote({
    required String notebookId,
    required String title,
    String content = '',
    List<String> tagIds = const [],
  }) =>
      _service.createNote(
        notebookId: notebookId,
        title: title,
        content: content,
        tagIds: tagIds,
      );

  @override
  Future<Note> updateNote({
    required String noteId,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isStarred,
  }) =>
      _service.updateNote(
        noteId: noteId,
        title: title,
        content: content,
        tagIds: tagIds,
        isStarred: isStarred,
      );

  @override
  Future<void> deleteNote(String noteId) => _service.deleteNote(noteId);

  @override
  Future<List<Tag>> listTags() => _service.listTags();

  @override
  Future<Tag> createTag(String name) => _service.createTag(name);

  @override
  Future<List<Note>> search({required String keyword}) =>
      _service.search(keyword: keyword);
}
