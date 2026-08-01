import '../core/services/note_station_service.dart';
import '../models/note.dart';
import '../models/note_version.dart';
import '../models/notebook.dart';
import '../models/shelf.dart';
import '../models/smart_notebook.dart';
import '../models/tag.dart';
import '../models/todo.dart';
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
  Future<Notebook> renameNotebook(
          {required String notebookId, required String title}) =>
      _service.renameNotebook(notebookId: notebookId, title: title);

  @override
  Future<List<Note>> listNotes({String? notebookId}) =>
      _service.listNotes(notebookId: notebookId);

  @override
  Future<Note> getNote(String noteId, {String? ver}) =>
      _service.getNote(noteId, ver: ver);

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
    String? notebookId,
  }) =>
      _service.updateNote(
        noteId: noteId,
        title: title,
        content: content,
        tagIds: tagIds,
        isStarred: isStarred,
        notebookId: notebookId,
      );

  @override
  Future<void> deleteNote(String noteId) => _service.deleteNote(noteId);

  @override
  Future<void> purgeNote(String noteId) => _service.purgeNote(noteId);

  @override
  Future<void> restoreNote(String noteId) => _service.restoreNote(noteId);

  @override
  Future<List<Note>> listTrashedNotes() async {
    final info = await _service.getInfo();
    return _service.listTrashedNotes(ownerUid: info.uid);
  }

  @override
  Future<List<Tag>> listTags() => _service.listTags();

  @override
  Future<Tag> createTag(String name) => _service.createTag(name);

  @override
  Future<List<Note>> search({required String keyword}) =>
      _service.search(keyword: keyword);

  @override
  Future<Note> encryptNote(
      {required Note note, required String password}) async {
    final encrypted =
        await _service.encryptNoteAsCopy(plainNote: note, password: password);
    // The stock client leaves the plaintext original behind (see
    // Note.Encrypt.write.txt) — trash it so encrypting never leaves readable
    // plaintext sitting next to the new encrypted copy.
    await _service.deleteNote(note.id);
    return encrypted;
  }

  @override
  Future<Note> uploadNoteAttachment({
    required Note note,
    required String content,
    required String fileName,
    required List<int> fileBytes,
    required String ref,
  }) =>
      _service.uploadNoteAttachment(
        note: note,
        content: content,
        fileName: fileName,
        fileBytes: fileBytes,
        ref: ref,
      );

  @override
  Future<List<NoteVersion>> listNoteVersions(String noteId) =>
      _service.listNoteVersions(noteId);

  @override
  Future<Note> restoreNoteVersion({
    required String noteId,
    required String ver,
  }) =>
      _service.restoreNoteVersion(noteId: noteId, ver: ver);

  @override
  Future<List<Todo>> listTodos({String? parentId}) =>
      _service.listTodos(parentId: parentId);

  @override
  Future<Todo> createTodo(
          {required String title, DateTime? dueDate, String? parentId}) =>
      _service.createTodo(title: title, dueDate: dueDate, parentId: parentId);

  @override
  Future<void> updateTodo({
    required String todoId,
    String? title,
    String? comment,
    bool? done,
    bool? star,
    int? priority,
    DateTime? dueDate,
  }) =>
      _service.updateTodo(
        todoId: todoId,
        title: title,
        comment: comment,
        done: done,
        star: star,
        priority: priority,
        dueDate: dueDate,
      );

  @override
  Future<void> deleteTodo(String todoId) => _service.deleteTodo(todoId);

  @override
  Future<List<SmartNotebook>> listSmartNotebooks() =>
      _service.listSmartNotebooks();

  @override
  Future<SmartNotebook> createSmartNotebook({
    required String title,
    required SmartCriteria criteria,
  }) async {
    // The wire format encodes tags as "<name>@<uid>" — resolve the current
    // user's uid once here so callers don't need to know about it.
    final info = await _service.getInfo();
    return _service.createSmartNotebook(
      title: title,
      criteria: criteria,
      ownerUid: info.uid,
    );
  }

  @override
  Future<List<Note>> listNotesForSmart(String smartId) async {
    final info = await _service.getInfo();
    return _service.listNotesInSmart(smartId: smartId, ownerUid: info.uid);
  }

  @override
  Future<String> getPublicShareLink(String noteId) =>
      _service.getPublicShareLink(noteId);

  @override
  Future<void> setSharingEnabled(String noteId, bool enabled) =>
      _service.setSharingEnabled(noteId, enabled);

  @override
  Future<void> setPublicPermission(String noteId, String perm) =>
      _service.setPublicPermission(noteId, perm);

  @override
  Future<void> deletePublicPermission(String noteId) =>
      _service.deletePublicPermission(noteId);

  @override
  Future<void> setGroupPermission({
    required String noteId,
    required String groupName,
    required String perm,
  }) =>
      _service.setGroupPermission(
          noteId: noteId, groupName: groupName, perm: perm);

  @override
  Future<void> setUserPermission({
    required String noteId,
    required String username,
    required String perm,
  }) =>
      _service.setUserPermission(
          noteId: noteId, username: username, perm: perm);

  @override
  Future<void> deleteUserPermission({
    required String noteId,
    required String username,
    required String uid,
  }) =>
      _service.deleteUserPermission(
          noteId: noteId, username: username, uid: uid);

  @override
  Future<void> deleteGroupPermission({
    required String noteId,
    required String groupName,
    required String gid,
  }) =>
      _service.deleteGroupPermission(
          noteId: noteId, groupName: groupName, gid: gid);

  @override
  Future<List<({String name, String type})>> searchSharePriv(String query) =>
      _service.searchSharePriv(query);

  @override
  Future<String> startNotebookExport({
    String? notebookId,
    required String destPath,
    bool exportTodo = true,
  }) =>
      _service.startNotebookExport(
        notebookId: notebookId,
        destPath: destPath,
        exportTodo: exportTodo,
      );

  @override
  Future<({bool finished, int current, int total})>
      getNotebookExportStatus() => _service.getNotebookExportStatus();

  @override
  Future<String> startNotebookImport({
    required String fileName,
    required String nasPath,
  }) =>
      _service.startNotebookImport(fileName: fileName, nasPath: nasPath);

  @override
  Future<({bool finished, int current, int total})>
      getNotebookImportStatus() => _service.getNotebookImportStatus();
}
