import '../api/synology_api_client.dart';
import '../crypto/note_crypto.dart';
import '../../models/note.dart';
import '../../models/notebook.dart';
import '../../models/shelf.dart';
import '../../models/note_version.dart';
import '../../models/smart_notebook.dart';
import '../../models/tag.dart';
import '../../models/todo.dart';

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

  /// [ver] fetches a specific historical revision's content instead of the
  /// current one — VERIFIED (`.docs/reference/Version restore*.har`): the
  /// same `Note.get` call, just with an extra `ver` param set to one of
  /// [listNoteVersions]'s `NoteVersion.ver` values.
  Future<Note> getNote(String noteId, {String? ver}) async {
    // VERIFIED (Note.CRUD capture): Note.get is v3, takes only `object_id`
    // (content is returned by default — no include_* flags), and the note
    // object is returned DIRECTLY under `data` (not data.note).
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'get',
      params: {
        'object_id': noteId,
        if (ver != null) 'ver': ver,
      },
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
    String? notebookId,
  }) async {
    return _setNote(
      objectId: noteId,
      title: title,
      content: content,
      tagIds: tagIds,
      isStarred: isStarred,
      notebookId: notebookId,
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
    String? notebookId,
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
    // NOT independently verified against a real capture of Note.set — inferred
    // by symmetry with Note.create/Note.copy, which both accept parent_id as a
    // plain field on the same note object. See NoteStation API documentation.md.
    if (notebookId != null) params['parent_id'] = notebookId;

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
  static String _briefFromHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Uploads [fileBytes] as a new image attachment while saving [content]
  /// (which must already contain the `<img ref="$ref">` tag for this upload)
  /// — VERIFIED (2026-07-25 HAR capture): NoteStation attaches images via
  /// `Note.set` itself, sent as multipart/form-data instead of the usual
  /// form-urlencoded, not a separate upload API. [ref] is caller-generated
  /// (the capture used base64(epoch_ms + filename)) and must match the `ref`
  /// attribute already embedded in [content]'s `<img>` tag.
  ///
  /// Same partial-response shape as [_setNote] (`data.data[0]`), but this one
  /// also carries fresh `link_id`/`attachment` alongside `ver` — the capture
  /// showed `attachment` there containing only the newly-created entry, not
  /// the note's full attachment set, so this merges onto [note]'s existing
  /// map rather than replacing it.
  Future<Note> uploadNoteAttachment({
    required Note note,
    required String content,
    required String fileName,
    required List<int> fileBytes,
    required String ref,
  }) async {
    final data = await _client.callMultipart(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'set',
      fields: {
        'commit_msg': {'device': 'desktop', 'listable': false},
        'object_id': note.id,
        if (note.ver != null) 'ver': note.ver,
        'content': content,
        'brief': _briefFromHtml(content),
        'check_conflict': true,
        'attachment': [
          {
            'action': 'create',
            'name': fileName,
            'format': 'raw',
            'source': fileName,
            'ref': ref,
            'rotate': true,
          },
        ],
      },
      fileFieldName: fileName,
      fileBytes: fileBytes,
      fileName: fileName,
    );

    final rows = data['data'] as List<dynamic>?;
    final row = (rows != null && rows.isNotEmpty)
        ? rows.first as Map<String, dynamic>
        : const <String, dynamic>{};
    return note.copyWith(
      content: content,
      ver: row['ver'] as String? ?? note.ver,
      linkId: row['link_id'] as String? ?? note.linkId,
      attachment: {
        ...note.attachment,
        ...?row['attachment'] as Map<String, dynamic>?,
      },
    );
  }

  /// Moves a note to trash. VERIFIED (Note.Ghost.txt, and again in
  /// `.docs/reference/Recyling Bin Delete and Restore*.har`): this is a soft
  /// delete — `method=delete` with `recycle=true` just flips the note's
  /// `recycle` flag; `object_id` is a JSON array (batch-capable) even for
  /// one note. See [purgeNote] for the same endpoint's OTHER behavior.
  Future<void> deleteNote(String noteId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'delete',
      params: {
        'object_id': [noteId],
        'recycle': true
      },
    );
  }

  /// Permanently deletes an ALREADY-trashed note. VERIFIED
  /// (`.docs/reference/Recyling Bin Delete and Restore*.har`): same
  /// endpoint/method as [deleteNote], but `recycle: false` — applied to a
  /// note that's already in the recycle bin, this purges it instead of
  /// trashing it (there is no separate purge method; the meaning of
  /// `recycle:false` depends on the note's current state). Calling this on
  /// a note that ISN'T already trashed has not been captured/tested.
  Future<void> purgeNote(String noteId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'delete',
      params: {
        'object_id': [noteId],
        'recycle': false,
      },
    );
  }

  /// Restores a trashed note back to its original notebook. VERIFIED: a
  /// dedicated `method=restore` on the same `SYNO.NoteStation.Note` API (not
  /// `Note.Version`'s own `restore`, which is a different endpoint for a
  /// different purpose — see [restoreNoteVersion]). `object_id` is a JSON
  /// array. The server evidently tracks where to put it back on its own
  /// (each trashed note's `old_parent_id` field, visible on the note object,
  /// though this call doesn't need to pass it explicitly).
  Future<void> restoreNote(String noteId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'restore',
      params: {
        'object_id': [noteId],
      },
    );
  }

  /// Lists trashed notes. VERIFIED: same `Note.list` v3 endpoint as
  /// [listNotes], `filter.recycle:true` instead of `false` — but the capture
  /// ALSO included `owner` explicitly in the filter (`listNotes()` doesn't,
  /// and has worked fine without it), so this mirrors the capture exactly
  /// as its own method rather than folding into `listNotes()`, same
  /// reasoning as [listNotesInSmart].
  Future<List<Note>> listTrashedNotes({
    required int ownerUid,
    int offset = 0,
    int limit = 50,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'list',
      params: {
        'filter': {'recycle': true, 'owner': ownerUid, 'archive': false},
        'field': {'link_id': true, 'commit_msg': true},
        'offset': offset,
        'limit': limit,
        'sort_by': 'title',
        'sort_direction': 'desc',
      },
    );
    final list = data['notes'] as List<dynamic>? ?? [];
    return list.map((j) => Note.fromJson(j as Map<String, dynamic>)).toList();
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

  // ── Version history ──────────────────────────────────────────────────────────

  /// VERIFIED: `object_id`, `limit`, `filter: {listable: true}`. Response
  /// `versions[].version` (a sha — NOT named `ver` in the response, despite
  /// being the exact value both `Note.get`'s `ver` param and
  /// `Note.Version restore`'s `ver` param key on) is newest-last in the
  /// capture's 3-version example.
  Future<List<NoteVersion>> listNoteVersions(String noteId) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note.Version',
      version: 2,
      method: 'list',
      params: {
        'object_id': noteId,
        'limit': 100,
        'filter': {'listable': true},
      },
    );
    final list = data['versions'] as List<dynamic>? ?? [];
    return list
        .map((j) => NoteVersion.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Restores the note to [ver] IN PLACE — VERIFIED: this is a real content
  /// mutation (not just a "preview"), the response comes back with
  /// `commit_msg.action: "restore"` and a fresh `ver`/`mtime`, same shape as
  /// a normal `Note.get`.
  Future<Note> restoreNoteVersion({
    required String noteId,
    required String ver,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note.Version',
      version: 2,
      method: 'restore',
      params: {'object_id': noteId, 'ver': ver},
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

  // ── Account info ────────────────────────────────────────────────────────────

  /// VERIFIED (present in every capture's startup compound call, and stands
  /// on its own fine outside a compound too): no params, returns
  /// {allow_share, hash, is_admin, uid, username, version}. Needed for
  /// Smart-notebook tag criteria, which encode tags as `"<name>@<uid>"`.
  Future<({int uid, String username, bool isAdmin})> getInfo() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Info',
      version: 2,
      method: 'get',
    );
    return (
      uid: data['uid'] as int? ?? 0,
      username: data['username'] as String? ?? '',
      isAdmin: data['is_admin'] as bool? ?? false,
    );
  }

  // ── Todo ────────────────────────────────────────────────────────────────────

  /// VERIFIED (`.docs/reference/To Do list capture*.har`): v2,
  /// `field.items:true` requests subtasks inline (always empty in every
  /// capture so far — subtask creation itself was never captured).
  /// [parentId] fetches only the subtasks of that parent — VERIFIED
  /// (`.docs/reference/Substasks*.har`) shape (`filter.parent_id`), now
  /// confirmed to actually return data once the parent has real subtasks
  /// (earlier captures only ever probed this filter against a childless
  /// task and got an empty result back).
  Future<List<Todo>> listTodos({String? parentId}) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Todo',
      version: 2,
      method: 'list',
      params: {
        'field': {'items': true},
        if (parentId != null) 'filter': {'parent_id': parentId},
      },
    );
    final list = data['todos'] as List<dynamic>? ?? [];
    return list.map((j) => Todo.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// VERIFIED: title-only, title+due_date, and title+parent_id (subtask —
  /// `.docs/reference/Substasks*.har`) variants all captured. The created
  /// to-do is returned directly under `data` (like Note.create).
  Future<Todo> createTodo({
    required String title,
    DateTime? dueDate,
    String? parentId,
  }) async {
    final params = <String, dynamic>{'title': title};
    if (dueDate != null) {
      params['due_date'] = dueDate.millisecondsSinceEpoch ~/ 1000;
    }
    if (parentId != null) params['parent_id'] = parentId;
    final data = await _client.call(
      api: 'SYNO.NoteStation.Todo',
      version: 2,
      method: 'create',
      params: params,
    );
    return Todo.fromJson(data);
  }

  /// Applies any combination of field edits to an existing to-do.
  /// VERIFIED: comment/priority/star/done were each captured as their own
  /// independent `set` call, `object_id` as a JSON array. `title`/`due_date`
  /// were only ever captured at CREATE time, never as a later edit — included
  /// here by strong symmetry with the same generic multi-field object-update
  /// shape (comparable to Note.set's inferred `parent_id`).
  Future<void> updateTodo({
    required String todoId,
    String? title,
    String? comment,
    bool? done,
    bool? star,
    int? priority,
    DateTime? dueDate,
  }) async {
    final params = <String, dynamic>{
      'object_id': [todoId],
    };
    if (title != null) params['title'] = title;
    if (comment != null) params['comment'] = comment;
    if (done != null) params['done'] = done;
    if (star != null) params['star'] = star;
    if (priority != null) params['priority'] = priority;
    if (dueDate != null) {
      params['due_date'] = dueDate.millisecondsSinceEpoch ~/ 1000;
    }
    await _client.call(
      api: 'SYNO.NoteStation.Todo',
      version: 2,
      method: 'set',
      params: params,
    );
  }

  /// VERIFIED (To Do list capture delete): unlike list/create/set (v2),
  /// delete is v1. `object_id` is a JSON array.
  Future<void> deleteTodo(String todoId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Todo',
      version: 1,
      method: 'delete',
      params: {
        'object_id': [todoId],
      },
    );
  }

  // ── Smart notebooks ─────────────────────────────────────────────────────────

  Future<List<SmartNotebook>> listSmartNotebooks() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Smart',
      version: 1,
      method: 'list',
    );
    final list = data['smarts'] as List<dynamic>? ?? [];
    return list
        .map((j) => SmartNotebook.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// VERIFIED (`.docs/reference/Smart Notebook*.har`) — the "critical"
  /// capture per the checklist, since it reveals nested/array param encoding:
  /// `query.tag` is an array of `"<tagName>@<uid>"` strings (the tag's NAME,
  /// not its id!), `query.parent_id` restricts to specific notebooks, both
  /// arrays even for one value. `Smart.list` does NOT echo the query back
  /// (see SmartCriteria's doc comment), so the returned [SmartNotebook]
  /// carries [criteria] only in this app's own in-memory state.
  Future<SmartNotebook> createSmartNotebook({
    required String title,
    required SmartCriteria criteria,
    required int ownerUid,
  }) async {
    final query = <String, dynamic>{};
    if (criteria.keyword != null && criteria.keyword!.isNotEmpty) {
      query['keyword'] = criteria.keyword;
    }
    if (criteria.innerTitle != null && criteria.innerTitle!.isNotEmpty) {
      query['title'] = criteria.innerTitle;
    }
    if (criteria.tagNames.isNotEmpty) {
      query['tag'] =
          criteria.tagNames.map((name) => '$name@$ownerUid').toList();
      query['tag_operator'] = criteria.tagOperator;
    }
    if (criteria.notebookIds.isNotEmpty) {
      query['parent_id'] = criteria.notebookIds;
    }

    final data = await _client.call(
      api: 'SYNO.NoteStation.Smart',
      version: 1,
      method: 'create',
      params: {
        'title': title,
        'query': query,
        'commit_msg': {'device': 'desktop'},
      },
    );
    return SmartNotebook(
      id: data['object_id']?.toString() ?? '',
      title: title,
    );
  }

  /// Lists the notes matching a smart notebook's saved query — i.e. what
  /// "opening" one actually does. VERIFIED (`.docs/reference/Create and Open
  /// Smart Notebook*.har`): NOT a separate endpoint — the same `Note.list`
  /// v3 call, scoped via two extra top-level params (`perm_from:"smart"`,
  /// `smart_id`) instead of `filter.parent_id`. The capture's `filter`/
  /// `field` shape differed slightly from a normal listNotes() call (no
  /// `archive` key in filter; `field` empty rather than requesting
  /// `link_id`/`commit_msg`) — mirrored exactly as captured rather than
  /// reusing listNotes()'s shape, since that difference is unexplained and
  /// might matter (e.g. a smart-sourced note missing `link_id` would break
  /// image resolution if assumed present).
  Future<List<Note>> listNotesInSmart({
    required String smartId,
    required int ownerUid,
    int offset = 0,
    int limit = 50,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Note',
      version: 3,
      method: 'list',
      params: {
        'filter': {'recycle': false, 'owner': ownerUid},
        'field': {},
        'offset': offset,
        'limit': limit,
        'sort_by': 'title',
        'sort_direction': 'desc',
        'perm_from': 'smart',
        'smart_id': smartId,
      },
    );
    final list = data['notes'] as List<dynamic>? ?? [];
    return list.map((j) => Note.fromJson(j as Map<String, dynamic>)).toList();
  }

  // ── Sharing / Permissions ────────────────────────────────────────────────────

  /// Public share link URL for [noteId]. VERIFIED (Note Sharing capture):
  /// mode="public"; "private" mode is unconfirmed (never captured).
  Future<String> getPublicShareLink(String noteId) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Shard.Link',
      version: 1,
      method: 'get',
      params: {'object_id': noteId, 'mode': 'public'},
    );
    return data['url'] as String? ?? '';
  }

  /// Turns note-level sharing on/off as a whole — VERIFIED, always sent
  /// alongside a Permission.Public/Permission.Group set in the capture (as
  /// two separate sequential calls here; the capture batched them via a
  /// SYNO.Entry.Request compound, but each entry in a compound is itself an
  /// independent call, not a transaction, so issuing them one after another
  /// has the same effect without needing a new compound-call code path).
  Future<void> setSharingEnabled(String noteId, bool enabled) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission',
      version: 1,
      method: 'set',
      params: {'object_id': noteId, 'enabled': enabled},
    );
  }

  /// VERIFIED: "ro". "rw" was only directly captured on [setUserPermission],
  /// not this endpoint specifically — but the wire shape (object_id + perm)
  /// is identical across Public/Group/User, so "rw" here is inferred by
  /// symmetry rather than independently confirmed.
  Future<void> setPublicPermission(String noteId, String perm) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission.Public',
      version: 1,
      method: 'set',
      params: {'object_id': noteId, 'perm': perm},
    );
  }

  /// VERIFIED (Note Sharing capture, revoke pass): removes the public link
  /// entirely rather than setting some "none" perm value.
  Future<void> deletePublicPermission(String noteId) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission.Public',
      version: 1,
      method: 'delete',
      params: {'object_id': noteId},
    );
  }

  /// VERIFIED: shares with a DSM group ("administrators" in the capture),
  /// perm "ro" directly captured here (see setPublicPermission's note — "rw"
  /// is inferred by symmetry for this specific endpoint, confirmed on
  /// [setUserPermission] instead).
  Future<void> setGroupPermission({
    required String noteId,
    required String groupName,
    required String perm,
  }) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission.Group',
      version: 1,
      method: 'set',
      params: {'object_id': noteId, 'groupname': groupName, 'perm': perm},
    );
  }

  /// Shares with an individual DSM user. VERIFIED
  /// (`.docs/reference/Share RW*.har`): `username` (not `groupname`), and
  /// `perm: "rw"` confirmed working here (not just "ro") — the note's `acl`
  /// came back with a new `dsm_user` entry afterward.
  Future<void> setUserPermission({
    required String noteId,
    required String username,
    required String perm,
  }) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission.User',
      version: 1,
      method: 'set',
      params: {'object_id': noteId, 'username': username, 'perm': perm},
    );
  }

  /// Revokes a single user's share. VERIFIED (`.docs/reference/Revoke
  /// Share*.har`): unlike [deletePublicPermission] (object_id only), this
  /// needs BOTH `username` and `uid` — `uid` is sent as a BARE JSON NUMBER
  /// (`"uid":1024`, not `"uid":"1024"`), even though it's the same value
  /// that appears as a string map-key in `Note.acl`'s `dsm_user`
  /// ([NoteUserShare.uid]) — [uid] here takes that string and parses it back
  /// to an int for the wire. No equivalent capture exists yet for removing a
  /// single GROUP's share.
  Future<void> deleteUserPermission({
    required String noteId,
    required String username,
    required String uid,
  }) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission.User',
      version: 1,
      method: 'delete',
      params: {
        'object_id': noteId,
        'username': username,
        'uid': int.parse(uid),
      },
    );
  }

  /// Revokes a single group's share. UNVERIFIED — no capture of this
  /// specific call exists yet. Built by symmetry with [deleteUserPermission]
  /// (per Aaron's explicit go-ahead 2026-07-31, to be re-captured/corrected
  /// if it doesn't actually work): mirrors [setGroupPermission]'s
  /// `groupname` naming, plus a `gid` counterpart to `deleteUserPermission`'s
  /// `uid` (also a bare JSON number, same reasoning) — using
  /// [NoteGroupShare.groupId], the same numeric-looking key `Note.acl`'s
  /// `dsm_group` map already carries. If this silently no-ops or errors on
  /// a real NAS, the shape to double-check first is this `gid` param —
  /// capture the real request and fix here.
  Future<void> deleteGroupPermission({
    required String noteId,
    required String groupName,
    required String gid,
  }) async {
    await _client.call(
      api: 'SYNO.NoteStation.Permission.Group',
      version: 1,
      method: 'delete',
      params: {
        'object_id': noteId,
        'groupname': groupName,
        'gid': int.parse(gid),
      },
    );
  }

  /// Autocomplete search over DSM users/groups for sharing. VERIFIED: returns
  /// {name, type: "user"|"group"} — feeds either [setUserPermission] or
  /// [setGroupPermission] depending on which type was picked.
  Future<List<({String name, String type})>> searchSharePriv(
      String query) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Share.Priv',
      version: 2,
      method: 'list',
      params: {'query': query},
    );
    final list = data['list'] as List<dynamic>? ?? [];
    return list.map((j) {
      final m = j as Map<String, dynamic>;
      return (
        name: m['name'] as String? ?? '',
        type: m['type'] as String? ?? 'user',
      );
    }).toList();
  }

  // ── Server-side .nsx export/import job ──────────────────────────────────────
  //
  // Distinct from this app's own local NsxCodec/NsxService (which parse/build
  // the .nsx ZIP format directly, client-side). This is the real NAS's own
  // async job: it writes/reads an .nsx file to/from a folder ON THE NAS
  // itself — moving that file to/from this device still needs a separate
  // FileStation upload/download, which is not yet built (no FileStation
  // folder-browse capture exists), so callers here take a plain NAS path
  // string rather than a folder-picker.

  /// VERIFIED (`.docs/reference/Export nsx and Import*.har`): [notebookId]
  /// null exports every notebook — the capture showed this sent as a literal
  /// JSON `null`, not an omitted param, hence [explicitNull]. [destPath] is a
  /// NAS-relative folder path (capture used "/Downloads").
  Future<String> startNotebookExport({
    String? notebookId,
    required String destPath,
    bool exportTodo = true,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Export.Notebook',
      version: 1,
      method: 'start',
      params: {
        'object_id': notebookId ?? explicitNull,
        'save_config': false,
        'dest': destPath,
        'export_todo': exportTodo,
      },
    );
    return data['task_id'] as String? ?? '';
  }

  /// Polls the export job's progress. VERIFIED shape: no params; response
  /// has `finish`(bool) and `data.current`/`data.total`.
  Future<({bool finished, int current, int total})>
      getNotebookExportStatus() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Export.Notebook',
      version: 1,
      method: 'status',
    );
    final progress = data['data'] as Map<String, dynamic>? ?? {};
    return (
      finished: data['finish'] as bool? ?? false,
      current: progress['current'] as int? ?? 0,
      total: progress['total'] as int? ?? 0,
    );
  }

  /// Starts an import job reading an `.nsx` already sitting in a NAS folder
  /// (see the class-of-methods doc comment above — the file must already be
  /// on the NAS; this doesn't upload one from the device). VERIFIED: `file`
  /// is an array of {name, format:"ds", path}.
  Future<String> startNotebookImport({
    required String fileName,
    required String nasPath,
  }) async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Import.Notebook',
      version: 1,
      method: 'start',
      params: {
        'file': [
          {'name': fileName, 'format': 'ds', 'path': nasPath},
        ],
      },
    );
    return data['task_id'] as String? ?? '';
  }

  /// Polls the import job's progress — same shape as the export status.
  Future<({bool finished, int current, int total})>
      getNotebookImportStatus() async {
    final data = await _client.call(
      api: 'SYNO.NoteStation.Import.Notebook',
      version: 1,
      method: 'status',
    );
    final progress = data['data'] as Map<String, dynamic>? ?? {};
    return (
      finished: data['finish'] as bool? ?? false,
      current: progress['current'] as int? ?? 0,
      total: progress['total'] as int? ?? 0,
    );
  }
}
