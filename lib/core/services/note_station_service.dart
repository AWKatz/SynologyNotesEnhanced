import '../api/synology_api_client.dart';
import '../crypto/note_crypto.dart';
import '../../models/note.dart';
import '../../models/notebook.dart';
import '../../models/shelf.dart';
import '../../models/tag.dart';

/// High-level service wrapping all SYNO.NoteStation.* API calls.
class NoteStationService {
  final SynologyApiClient _client;

  NoteStationService(this._client);

  // ── Shelves (Stacks) ────────────────────────────────────────────────────────

  Future<List<Shelf>> listShelves() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Stack',
      version: 1,
      method: 'list',
    );
    final list = data['stacks'] as List<dynamic>? ?? [];
    return list.map((j) => Shelf.fromJson(j as Map<String, dynamic>)).toList();
  }

  // ── Notebooks ───────────────────────────────────────────────────────────────

  Future<List<Notebook>> listNotebooks() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Notebook',
      version: 2,
      method: 'list',
    );
    final list = data['notebooks'] as List<dynamic>? ?? [];
    return list
        .map((j) => Notebook.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Notebook> createNotebook({
    required String title,
    String? shelfId,
  }) async {
    final params = <String, dynamic>{'title': title};
    if (shelfId != null) params['stack_id'] = shelfId;

    final data = await _client.call(
      api: 'SYNO.NoteStation.Notebook',
      version: 2,
      method: 'create',
      params: params,
    );
    return Notebook.fromJson(data['notebook'] as Map<String, dynamic>);
  }

  Future<void> deleteNotebook(String notebookId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Notebook',
      version: 2,
      method: 'delete',
      // VERIFIED: Notebook objects are keyed by `object_id`.
      params: {'object_id': notebookId},
    );
  }

  Future<Notebook> renameNotebook({
    required String notebookId,
    required String title,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Notebook',
      version: 2,
      method: 'update',
      // VERIFIED: Notebook objects are keyed by `object_id`.
      params: {'object_id': notebookId, 'title': title},
    );
    return Notebook.fromJson(data['notebook'] as Map<String, dynamic>);
  }

  // ── Notes ───────────────────────────────────────────────────────────────────

  Future<List<Note>> listNotes({
    String? notebookId,
    int offset = 0,
    int limit = 100,
    String sortBy = 'title',
    String order = 'desc',
  }) async {
    // Verified shape from captures/Sync.Entry.Request.txt §2: Note.list is v3 with
    // structured `filter`/`field` objects and `sort_direction` (not v4/order/fields-csv).
    final filter = <String, dynamic>{'recycle': false, 'archive': false};
    // INFERRED: scoping a list to one notebook via filter.parent_id (not yet captured).
    if (notebookId != null) filter['parent_id'] = notebookId;

    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'list',
      params: {
        'filter': filter,
        'field': {'link_id': true, 'commit_msg': true},
        'offset': offset,
        'limit': limit,
        'sort_by': sortBy,
        'sort_direction': order,
      },
    );
    final list = data['notes'] as List<dynamic>? ?? [];
    return list.map((j) => Note.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Note> getNote(String noteId) async {
    // VERIFIED (Note.CRUD capture): Note.get is v3, takes only `object_id`
    // (content is returned by default — no include_* flags), and the note
    // object is returned DIRECTLY under `data` (not data.note).
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'get',
      params: {'object_id': noteId},
    );
    return Note.fromJson(data);
  }

  Future<Note> createNote({
    required String notebookId,
    required String title,
    String content = '',
    List<String> tagIds = const [],
  }) async {
    // VERIFIED (Note.CRUD capture): Note.create is v3 with commit_msg/title/
    // parent_id/encrypt and returns the new note DIRECTLY under `data`. The real
    // client creates an EMPTY note (no content/tag) then applies body & tags via
    // a follow-up Note.set, so we mirror that when content/tags are supplied.
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'create',
      params: {
        'commit_msg': {'device': 'desktop', 'listable': false},
        'title': title,
        'parent_id': notebookId,
        'encrypt': false,
      },
    );
    final created = Note.fromJson(data);

    if (content.isEmpty && tagIds.isEmpty) return created;
    return _setNote(
      objectId: created.id,
      ver: created.ver,
      content: content.isEmpty ? null : content,
      tagIds: tagIds.isEmpty ? null : tagIds,
    );
  }

  Future<Note> updateNote({
    required String noteId,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isStarred,
  }) async {
    return _setNote(
      objectId: noteId,
      title: title,
      content: content,
      tagIds: tagIds,
      isStarred: isStarred,
    );
  }

  /// Applies changes to an existing note via the VERIFIED Note.set v3 call.
  ///
  /// Note.set requires the note's current `ver` (sha1) for optimistic
  /// concurrency (`check_conflict=true`); when [ver] is not supplied we fetch
  /// the latest first. NOTE: auto-fetching the latest ver means concurrent
  /// edits are last-writer-wins rather than conflict-rejected — thread the
  /// caller's known `ver` through to restore true conflict detection.
  ///
  /// Verified param shapes (Note.CRUD capture): `tag` is a JSON ARRAY (not a
  /// CSV string); content edits also send a plain-text `brief`; the response is
  /// a PARTIAL object under data.data[0] carrying the new `ver`.
  Future<Note> _setNote({
    required String objectId,
    String? ver,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isStarred,
  }) async {
    Note? current;
    if (ver == null) {
      current = await getNote(objectId);
      ver = current.ver;
    }

    final params = <String, dynamic>{
      'commit_msg': {'device': 'desktop'},
      'object_id': objectId,
      if (ver != null) 'ver': ver,
      'check_conflict': true,
    };
    if (title != null) params['title'] = title;
    if (content != null) {
      params['content'] = content;
      params['brief'] = _briefFromHtml(content);
    }
    if (tagIds != null) params['tag'] = tagIds; // JSON array, not CSV
    if (isStarred != null) params['is_starred'] = isStarred;

    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'set',
      params: params,
    );

    // Response is a partial under data.data[0] (new ver/mtime), not a full note.
    final rows = data['data'] as List<dynamic>?;
    final newVer = (rows != null && rows.isNotEmpty)
        ? (rows.first as Map<String, dynamic>)['ver'] as String?
        : null;

    // Return the note with the edits + fresh ver applied, avoiding a second get.
    current ??= Note(id: objectId, notebookId: '', title: title ?? '');
    return current.copyWith(
      title: title,
      content: content,
      tags: tagIds,
      isFavorite: isStarred,
      ver: newVer,
    );
  }

  /// Plain-text preview the way the web client derives `brief` from note HTML.
  static String _briefFromHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Moves a note to trash. VERIFIED (Note.Ghost.txt): this is a soft delete —
  /// `method=delete` with `recycle=true` just flips the note's `recycle` flag;
  /// `object_id` is a JSON array (batch-capable) even for one note. There is no
  /// verified restore/purge yet, so this only ever trashes, never destroys.
  Future<void> deleteNote(String noteId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'delete',
      params: {'object_id': [noteId], 'recycle': true},
    );
  }

  /// Encrypts a currently-plain note with [password]. VERIFIED
  /// (Note.Encrypt.write.txt): the stock client encrypts client-side (same
  /// AES-256-CBC/OpenSSL scheme as decrypt) and submits via `Note.copy`, which
  /// creates a NEW note object carrying the encrypted blob — it is NOT an
  /// in-place `Note.set`. The original plaintext note is left behind by the
  /// stock client; callers here are expected to trash it afterward (see
  /// `NasNotesRepository.encryptNote`) so a "successfully encrypted" note
  /// never leaves readable plaintext sitting next to it.
  Future<Note> encryptNoteAsCopy({
    required Note plainNote,
    required String password,
  }) async {
    final encryptedContent = NoteCrypto.encrypt(plainNote.content, password);
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'copy',
      params: {
        'commit_msg': {'device': 'desktop', 'listable': true},
        'object_id': plainNote.id,
        if (plainNote.ver != null) 'ver': plainNote.ver,
        'content': encryptedContent,
        'brief': _briefFromHtml(plainNote.content),
        'tag': plainNote.tags,
        'title': plainNote.title,
        'source_url': '',
        'latitude': 0,
        'longitude': 0,
        'location': '',
        'parent_id': plainNote.notebookId,
        'encrypt': true,
        'recycle': false,
        'new_password': password,
      },
    );
    return Note.fromJson(data);
  }

  // ── Tags ────────────────────────────────────────────────────────────────────

  Future<List<Tag>> listTags() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Tag',
      version: 2,
      method: 'list',
    );
    final list = data['tags'] as List<dynamic>? ?? [];
    return list.map((j) => Tag.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Tag> createTag(String name) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Tag',
      version: 2,
      method: 'create',
      params: {'name': name},
    );
    return Tag.fromJson(data['tag'] as Map<String, dynamic>);
  }

  // ── Full-text search ────────────────────────────────────────────────────────

  Future<List<Note>> search({
    required String keyword,
    int offset = 0,
    int limit = 50,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.FTS',
      version: 1,
      method: 'search',
      params: {
        'keyword': keyword,
        'offset': offset,
        'limit': limit,
      },
    );
    final list = data['notes'] as List<dynamic>? ?? [];
    return list.map((j) => Note.fromJson(j as Map<String, dynamic>)).toList();
  }
}
