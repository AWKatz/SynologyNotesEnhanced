import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/notebook.dart';
import '../models/shelf.dart';
import '../models/tag.dart';
import 'notes_repository.dart';

class LocalNotesRepository implements NotesRepository {
  Future<Directory> _dataDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/synologynotesenhanceds_local');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _file(String name) async {
    final dir = await _dataDir();
    return File('${dir.path}/$name');
  }

  Future<Directory> _notesDir() async {
    final dir = await _dataDir();
    final notesDir = Directory('${dir.path}/notes');
    if (!notesDir.existsSync()) notesDir.createSync();
    return notesDir;
  }

  Future<List<Map<String, dynamic>>> _readJsonList(String filename) async {
    final file = await _file(filename);
    if (!file.existsSync()) return [];
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (data['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeJsonList(String filename, List<Map<String, dynamic>> items) async {
    final file = await _file(filename);
    file.writeAsStringSync(jsonEncode({'items': items}));
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  // ── Shelves ─────────────────────────────────────────────────────────────────

  @override
  Future<List<Shelf>> listShelves() async {
    final items = await _readJsonList('shelves.json');
    return items.map((j) => Shelf.fromJson(j)).toList();
  }

  Future<Shelf> createShelf(String name) async {
    final items = await _readJsonList('shelves.json');
    final shelf = {'stack_id': _newId(), 'title': name};
    items.add(shelf);
    await _writeJsonList('shelves.json', items);
    return Shelf.fromJson(shelf);
  }

  // ── Notebooks ────────────────────────────────────────────────────────────────

  @override
  Future<List<Notebook>> listNotebooks() async {
    final items = await _readJsonList('notebooks.json');
    return items.map((j) => Notebook.fromJson(j)).toList();
  }

  @override
  Future<Notebook> createNotebook({required String title, String? shelfId}) async {
    final items = await _readJsonList('notebooks.json');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final nb = {
      'notebook_id': _newId(),
      'title': title,
      'stack_id': shelfId,
      'note_count': 0,
      'ctime': now,
      'mtime': now,
    };
    items.add(nb);
    await _writeJsonList('notebooks.json', items);
    return Notebook.fromJson(nb);
  }

  @override
  Future<void> deleteNotebook(String notebookId) async {
    var items = await _readJsonList('notebooks.json');
    items.removeWhere((j) => (j['notebook_id'] ?? j['id']) == notebookId);
    await _writeJsonList('notebooks.json', items);
    // Also delete notes in this notebook
    final notesIndex = await _readJsonList('notes_index.json');
    final toDelete = notesIndex
        .where((j) => j['notebook_id'] == notebookId)
        .map((j) => (j['note_id'] ?? j['id']).toString())
        .toList();
    for (final id in toDelete) {
      await deleteNote(id);
    }
  }

  @override
  Future<Notebook> renameNotebook({required String notebookId, required String title}) async {
    final items = await _readJsonList('notebooks.json');
    for (final item in items) {
      if ((item['notebook_id'] ?? item['id']) == notebookId) {
        item['title'] = title;
        item['mtime'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        break;
      }
    }
    await _writeJsonList('notebooks.json', items);
    return Notebook.fromJson(items.firstWhere(
      (j) => (j['notebook_id'] ?? j['id']) == notebookId,
    ));
  }

  // ── Notes ────────────────────────────────────────────────────────────────────

  @override
  Future<List<Note>> listNotes({String? notebookId}) async {
    final index = await _readJsonList('notes_index.json');
    final filtered = notebookId == null
        ? index
        : index.where((j) => j['notebook_id'] == notebookId).toList();
    return filtered.map((j) => Note.fromJson(j)).toList();
  }

  @override
  Future<Note> getNote(String noteId) async {
    final dir = await _notesDir();
    final file = File('${dir.path}/$noteId.json');
    if (!file.existsSync()) throw Exception('Note $noteId not found');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return Note.fromJson(data);
  }

  @override
  Future<Note> createNote({
    required String notebookId,
    required String title,
    String content = '',
    List<String> tagIds = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = _newId();
    final noteData = {
      'note_id': id,
      'notebook_id': notebookId,
      'title': title,
      'content': content.isEmpty ? '<p></p>' : content,
      'tag': tagIds,
      'ctime': now,
      'mtime': now,
      'is_starred': false,
      'is_encrypted': false,
      'snippet': content.replaceAll(RegExp(r'<[^>]+>'), ' ').trim(),
    };

    // Write full note file
    final dir = await _notesDir();
    File('${dir.path}/$id.json').writeAsStringSync(jsonEncode(noteData));

    // Update index
    final index = await _readJsonList('notes_index.json');
    final indexEntry = Map<String, dynamic>.from(noteData)..remove('content');
    index.add(indexEntry);
    await _writeJsonList('notes_index.json', index);

    // Update notebook note_count
    await _incrementNoteCount(notebookId, 1);

    return Note.fromJson(noteData);
  }

  @override
  Future<Note> updateNote({
    required String noteId,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isStarred,
  }) async {
    final existing = await getNote(noteId);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final updated = existing.copyWith(
      title: title,
      content: content,
      tags: tagIds,
      isFavorite: isStarred,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now * 1000),
    );

    final noteData = {
      'note_id': updated.id,
      'notebook_id': updated.notebookId,
      'title': updated.title,
      'content': updated.content,
      'tag': updated.tags,
      'ctime': updated.createdAt?.millisecondsSinceEpoch != null
          ? updated.createdAt!.millisecondsSinceEpoch ~/ 1000
          : now,
      'mtime': now,
      'is_starred': updated.isFavorite,
      'is_encrypted': updated.isEncrypted,
      'snippet': updated.content.replaceAll(RegExp(r'<[^>]+>'), ' ').trim(),
    };

    // Write full note file
    final dir = await _notesDir();
    File('${dir.path}/$noteId.json').writeAsStringSync(jsonEncode(noteData));

    // Update index
    final index = await _readJsonList('notes_index.json');
    final idx = index.indexWhere((j) => (j['note_id'] ?? j['id']) == noteId);
    if (idx != -1) {
      final indexEntry = Map<String, dynamic>.from(noteData)..remove('content');
      index[idx] = indexEntry;
      await _writeJsonList('notes_index.json', index);
    }

    return updated;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    // Get notebook id before deleting
    String? notebookId;
    try {
      final note = await getNote(noteId);
      notebookId = note.notebookId;
    } catch (_) {}

    final dir = await _notesDir();
    final file = File('${dir.path}/$noteId.json');
    if (file.existsSync()) file.deleteSync();

    final index = await _readJsonList('notes_index.json');
    index.removeWhere((j) => (j['note_id'] ?? j['id']) == noteId);
    await _writeJsonList('notes_index.json', index);

    if (notebookId != null) {
      await _incrementNoteCount(notebookId, -1);
    }
  }

  /// Imports notebooks + notes (e.g. parsed from a .nsx) into local storage,
  /// preserving their original ids, timestamps, tags, and — crucially — raw
  /// content including encrypted (`Salted__`) bodies, so offline decryption and
  /// formatting can be tested without the NAS. Existing ids are overwritten.
  /// Returns (#notebooks, #notes) imported.
  Future<(int, int)> importBundle(
      List<Notebook> notebooks, List<Note> notes) async {
    int sec(DateTime? dt) => dt == null
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : dt.millisecondsSinceEpoch ~/ 1000;

    // Notebooks: merge by id.
    final nbItems = await _readJsonList('notebooks.json');
    for (final nb in notebooks) {
      nbItems.removeWhere((j) => (j['notebook_id'] ?? j['id']) == nb.id);
      nbItems.add({
        'notebook_id': nb.id,
        'title': nb.name,
        'stack_id': nb.shelfId,
        'note_count': notes.where((n) => n.notebookId == nb.id).length,
        'ctime': sec(nb.createdAt),
        'mtime': sec(nb.updatedAt),
      });
    }
    await _writeJsonList('notebooks.json', nbItems);

    // Notes: write full file per note + rebuild index entries.
    final dir = await _notesDir();
    final index = await _readJsonList('notes_index.json');
    for (final note in notes) {
      final data = {
        'note_id': note.id,
        'notebook_id': note.notebookId,
        'title': note.title,
        'content': note.content,
        'tag': note.tags,
        'ctime': sec(note.createdAt),
        'mtime': sec(note.updatedAt),
        'is_starred': note.isFavorite,
        'is_encrypted': note.isEncrypted,
        'snippet': note.excerpt ??
            note.content.replaceAll(RegExp(r'<[^>]+>'), ' ').trim(),
      };
      File('${dir.path}/${note.id}.json').writeAsStringSync(jsonEncode(data));
      index.removeWhere((j) => (j['note_id'] ?? j['id']) == note.id);
      index.add(Map<String, dynamic>.from(data)..remove('content'));
    }
    await _writeJsonList('notes_index.json', index);

    return (notebooks.length, notes.length);
  }

  /// Collects every locally-stored notebook and note (full content) — the
  /// source for building a .nsx export in offline mode.
  Future<(List<Notebook>, List<Note>)> exportAll() async {
    final notebooks = await listNotebooks();
    final index = await listNotes();
    final notes = <Note>[];
    for (final stub in index) {
      try {
        notes.add(await getNote(stub.id));
      } catch (_) {
        notes.add(stub);
      }
    }
    return (notebooks, notes);
  }

  Future<void> _incrementNoteCount(String notebookId, int delta) async {
    final notebooks = await _readJsonList('notebooks.json');
    for (final nb in notebooks) {
      if ((nb['notebook_id'] ?? nb['id']) == notebookId) {
        final current = nb['note_count'] as int? ?? 0;
        nb['note_count'] = (current + delta).clamp(0, 999999);
        break;
      }
    }
    await _writeJsonList('notebooks.json', notebooks);
  }

  // ── Tags ──────────────────────────────────────────────────────────────────────

  @override
  Future<List<Tag>> listTags() async {
    final items = await _readJsonList('tags.json');
    return items.map((j) => Tag.fromJson(j)).toList();
  }

  @override
  Future<Tag> createTag(String name) async {
    final items = await _readJsonList('tags.json');
    final tag = {'tag_id': _newId(), 'name': name, 'count': 0};
    items.add(tag);
    await _writeJsonList('tags.json', items);
    return Tag.fromJson(tag);
  }

  // ── Search ────────────────────────────────────────────────────────────────────

  @override
  Future<List<Note>> search({required String keyword}) async {
    final allNotes = await listNotes();
    final q = keyword.toLowerCase();
    return allNotes.where((n) {
      return n.title.toLowerCase().contains(q) ||
          n.displayExcerpt.toLowerCase().contains(q);
    }).toList();
  }
}
