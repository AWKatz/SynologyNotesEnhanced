import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synologynotesenhanceds_enhanced/core/api/synology_api_client.dart';
import 'package:synologynotesenhanceds_enhanced/core/services/note_station_service.dart';
import 'package:synologynotesenhanceds_enhanced/models/smart_notebook.dart';

/// Parses an `application/x-www-form-urlencoded` body into a map.
Map<String, String> _form(String body) => Uri(query: body).queryParameters;

void main() {
  /// Builds a service whose mock transport captures request bodies and returns
  /// the given canned `data` envelope.
  (NoteStationService, List<Map<String, String>>) makeService(
      Object dataPayload) {
    final captured = <Map<String, String>>[];
    final mock = MockClient((req) async {
      captured.add(_form(req.body));
      return http.Response(
        jsonEncode({'success': true, 'data': dataPayload}),
        200,
      );
    });
    final client =
        SynologyApiClient.withSid('https://nas:5001', 'SID', httpClient: mock);
    return (NoteStationService(client), captured);
  }

  /// Mock that returns a different `data` envelope per (api, method), so the
  /// multi-call flows (create→set, get→set) can each get a sensible response.
  (NoteStationService, List<Map<String, String>>) makeRouter(
      Map<String, Object> byMethod) {
    final captured = <Map<String, String>>[];
    final mock = MockClient((req) async {
      final body = _form(req.body);
      captured.add(body);
      final key = body['method'] ?? '';
      final payload = byMethod[key] ?? <String, dynamic>{};
      return http.Response(
          jsonEncode({'success': true, 'data': payload}), 200);
    });
    final client =
        SynologyApiClient.withSid('https://nas:5001', 'SID', httpClient: mock);
    return (NoteStationService(client), captured);
  }

  group('Note CRUD uses verified conventions (v3 / object_id / set / data)', () {
    test('getNote: v3, object_id only, parses note straight from data', () async {
      // VERIFIED: note object lives directly under `data` (not data.note).
      final (svc, captured) = makeService(
          {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'T', 'ver': 'v1'});
      final note = await svc.getNote('N1');
      final body = captured.single;
      expect(body['version'], '3');
      expect(body['method'], 'get');
      expect(body['object_id'], '"N1"');
      expect(body.containsKey('include_content'), isFalse);
      expect(note.ver, 'v1');
      expect(note.notebookId, 'NB1');
    });

    test('createNote (empty): v3, parent_id, commit_msg, no content/tag',
        () async {
      final (svc, captured) = makeService(
          {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'T', 'ver': 'v1'});
      await svc.createNote(notebookId: 'NB1', title: 'T');
      final body = captured.single; // empty note → no follow-up set
      expect(body['version'], '3');
      expect(body['method'], 'create');
      expect(body['parent_id'], '"NB1"');
      expect(body.containsKey('content'), isFalse);
      expect(body.containsKey('tag'), isFalse);
      expect(jsonDecode(body['commit_msg']!), {'device': 'desktop', 'listable': false});
    });

    test('createNote (with content): create then set', () async {
      final (svc, captured) = makeRouter({
        'create': {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'T', 'ver': 'v1'},
        'set': {'data': [{'object_id': 'N1', 'ver': 'v2'}]},
      });
      final note = await svc.createNote(
          notebookId: 'NB1', title: 'T', content: '<p>hi</p>');
      expect(captured.map((b) => b['method']), ['create', 'set']);
      final set = captured[1];
      expect(set['object_id'], '"N1"');
      expect(set['ver'], '"v1"'); // ver from create response
      expect(set['content'], '"<p>hi</p>"');
      expect(note.ver, 'v2');
    });

    test('updateNote: method=set, fetches ver via get, tag is JSON array',
        () async {
      final (svc, captured) = makeRouter({
        'get': {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'old', 'ver': 'v1'},
        'set': {'data': [{'object_id': 'N1', 'ver': 'v2'}]},
      });
      final note = await svc.updateNote(
          noteId: 'N1', title: 'T2', tagIds: ['a', 'b']);
      expect(captured.map((b) => b['method']), ['get', 'set']);
      final set = captured[1];
      expect(set['version'], '3');
      expect(set['object_id'], '"N1"');
      expect(set['ver'], '"v1"');
      expect(set['check_conflict'], 'true');
      expect(set['title'], '"T2"');
      expect(jsonDecode(set['tag']!), ['a', 'b']); // array, not CSV
      expect(note.ver, 'v2');
    });
  });

  group('Notebook write methods key by object_id', () {
    test('deleteNotebook: object_id', () async {
      final (svc, captured) = makeService({});
      await svc.deleteNotebook('NB1');
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Notebook');
      expect(body['method'], 'delete');
      expect(body['object_id'], '"NB1"');
      expect(body.containsKey('notebook_id'), isFalse);
    });

    test('renameNotebook: object_id', () async {
      final (svc, captured) = makeService({
        'notebook': {'object_id': 'NB1', 'title': 'New'}
      });
      await svc.renameNotebook(notebookId: 'NB1', title: 'New');
      final body = captured.single;
      expect(body['method'], 'update');
      expect(body['object_id'], '"NB1"');
      expect(body['title'], '"New"');
      expect(body.containsKey('notebook_id'), isFalse);
    });
  });

  group('Version history (verified against Version restore*.har)', () {
    test('getNote with ver: adds ver param', () async {
      final (svc, captured) = makeService(
          {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'T', 'ver': 'v1'});
      await svc.getNote('N1', ver: 'v0');
      final body = captured.single;
      expect(body['object_id'], '"N1"');
      expect(body['ver'], '"v0"');
    });

    test('getNote without ver: no ver param sent', () async {
      final (svc, captured) = makeService(
          {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'T', 'ver': 'v1'});
      await svc.getNote('N1');
      expect(captured.single.containsKey('ver'), isFalse);
    });

    test('listNoteVersions: object_id, limit, filter.listable', () async {
      final (svc, captured) = makeService({
        'versions': [
          {'id': 1, 'version': 'sha1', 'author': 'Aaron', 'mtime': 100},
        ]
      });
      final versions = await svc.listNoteVersions('N1');
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Note.Version');
      expect(body['version'], '2');
      expect(body['method'], 'list');
      expect(body['object_id'], '"N1"');
      expect(body['limit'], '100');
      expect(jsonDecode(body['filter']!), {'listable': true});
      expect(versions.single.ver, 'sha1');
      expect(versions.single.author, 'Aaron');
    });

    test('restoreNoteVersion: object_id + ver, method=restore v2', () async {
      final (svc, captured) = makeService(
          {'object_id': 'N1', 'parent_id': 'NB1', 'title': 'T', 'ver': 'v2'});
      final note = await svc.restoreNoteVersion(noteId: 'N1', ver: 'v0');
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Note.Version');
      expect(body['version'], '2');
      expect(body['method'], 'restore');
      expect(body['object_id'], '"N1"');
      expect(body['ver'], '"v0"');
      expect(note.ver, 'v2');
    });
  });

  group('Todo (verified against To Do list capture*.har)', () {
    test('listTodos: v2, field.items requests subtasks inline', () async {
      final (svc, captured) = makeService({'todos': []});
      await svc.listTodos();
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Todo');
      expect(body['version'], '2');
      expect(body['method'], 'list');
      expect(jsonDecode(body['field']!), {'items': true});
    });

    test('createTodo: title-only and title+due_date', () async {
      final (svc, captured) = makeService(
          {'object_id': 'T1', 'title': 'x', 'done': false, 'priority': -1});
      await svc.createTodo(title: 'x');
      await svc.createTodo(
          title: 'y', dueDate: DateTime.fromMillisecondsSinceEpoch(1788210000 * 1000));
      expect(captured[0]['title'], '"x"');
      expect(captured[0].containsKey('due_date'), isFalse);
      expect(captured[1]['title'], '"y"');
      expect(captured[1]['due_date'], '1788210000'); // bare int, not quoted
    });

    test('updateTodo: object_id is a JSON array, only given fields present',
        () async {
      final (svc, captured) = makeService({});
      await svc.updateTodo(todoId: 'T1', star: true);
      final body = captured.single;
      expect(body['version'], '2');
      expect(body['method'], 'set');
      expect(jsonDecode(body['object_id']!), ['T1']);
      expect(body['star'], 'true');
      expect(body.containsKey('done'), isFalse);
      expect(body.containsKey('priority'), isFalse);
    });

    test('deleteTodo: version 1 (not 2 like list/create/set)', () async {
      final (svc, captured) = makeService({});
      await svc.deleteTodo('T1');
      final body = captured.single;
      expect(body['version'], '1');
      expect(body['method'], 'delete');
      expect(jsonDecode(body['object_id']!), ['T1']);
    });

    test('createTodo with parentId creates a subtask (Substasks*.har)',
        () async {
      final (svc, captured) = makeService(
          {'object_id': 'T2', 'title': 'sub', 'parent_id': 'T1'});
      await svc.createTodo(title: 'sub', parentId: 'T1');
      expect(captured.single['title'], '"sub"');
      expect(captured.single['parent_id'], '"T1"');
    });

    test('listTodos with parentId filters to that parent\'s subtasks',
        () async {
      final (svc, captured) = makeService({'todos': []});
      await svc.listTodos(parentId: 'T1');
      expect(jsonDecode(captured.single['filter']!), {'parent_id': 'T1'});
    });

    test('Todo.fromJson parses items as subtask id strings, not objects',
        () async {
      final (svc, captured) = makeService({
        'todos': [
          {
            'object_id': 'T1',
            'title': 'parent',
            'items': ['T2', 'T3'],
          }
        ]
      });
      final todos = await svc.listTodos();
      expect(captured, isNotEmpty); // sanity: call happened
      expect(todos.single.subtaskIds, ['T2', 'T3']);
    });
  });

  group('Smart notebooks (verified against Smart Notebook*.har)', () {
    test('listSmartNotebooks: v1, no params', () async {
      final (svc, captured) = makeService({'smarts': []});
      await svc.listSmartNotebooks();
      expect(captured.single['method'], 'list');
      expect(captured.single['api'], 'SYNO.NoteStation.Smart');
    });

    test('createSmartNotebook: tag array is "<name>@<uid>", parent_id array',
        () async {
      final (svc, captured) = makeService({'object_id': 'S1'});
      await svc.createSmartNotebook(
        title: 'Recipes',
        criteria: const SmartCriteria(
          keyword: 'SMART',
          innerTitle: 'THIS IS A SMART NOTEBOOK',
          tagNames: ["Mom's Recipies"],
          notebookIds: ['NB1'],
        ),
        ownerUid: 1026,
      );
      final body = captured.single;
      expect(body['version'], '1');
      expect(body['method'], 'create');
      final query = jsonDecode(body['query']!) as Map;
      expect(query['keyword'], 'SMART');
      expect(query['title'], 'THIS IS A SMART NOTEBOOK');
      expect(query['tag'], ["Mom's Recipies@1026"]);
      expect(query['tag_operator'], 'and');
      expect(query['parent_id'], ['NB1']);
    });

    test(
        'listNotesInSmart: perm_from/smart_id scope Note.list, not a '
        'separate endpoint (Create and Open Smart Notebook*.har)', () async {
      final (svc, captured) = makeService({'notes': []});
      await svc.listNotesInSmart(smartId: 'S1', ownerUid: 1026);
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Note');
      expect(body['method'], 'list');
      expect(body['perm_from'], '"smart"');
      expect(body['smart_id'], '"S1"');
      expect(jsonDecode(body['filter']!), {'recycle': false, 'owner': 1026});
      expect(jsonDecode(body['field']!), {});
    });
  });

  group('Sharing/Permissions (verified against Note Sharing*.har)', () {
    test('getPublicShareLink: mode=public', () async {
      final (svc, captured) = makeService({'url': 'https://x/ns/sharing/abc'});
      final url = await svc.getPublicShareLink('N1');
      expect(captured.single['api'], 'SYNO.NoteStation.Shard.Link');
      expect(captured.single['mode'], '"public"');
      expect(url, 'https://x/ns/sharing/abc');
    });

    test('setSharingEnabled', () async {
      final (svc, captured) = makeService({});
      await svc.setSharingEnabled('N1', true);
      expect(captured.single['api'], 'SYNO.NoteStation.Permission');
      expect(captured.single['enabled'], 'true');
    });

    test('setPublicPermission / deletePublicPermission', () async {
      final (svc, captured) = makeService({});
      await svc.setPublicPermission('N1', 'ro');
      await svc.deletePublicPermission('N1');
      expect(captured[0]['api'], 'SYNO.NoteStation.Permission.Public');
      expect(captured[0]['method'], 'set');
      expect(captured[0]['perm'], '"ro"');
      expect(captured[1]['method'], 'delete');
      expect(captured[1].containsKey('perm'), isFalse);
    });

    test('setGroupPermission: groupname + perm', () async {
      final (svc, captured) = makeService({});
      await svc.setGroupPermission(
          noteId: 'N1', groupName: 'administrators', perm: 'ro');
      expect(captured.single['api'], 'SYNO.NoteStation.Permission.Group');
      expect(captured.single['groupname'], '"administrators"');
    });

    test('setUserPermission: username + rw (verified against Share RW*.har)',
        () async {
      final (svc, captured) = makeService({});
      await svc.setUserPermission(noteId: 'N1', username: 'admin', perm: 'rw');
      expect(captured.single['api'], 'SYNO.NoteStation.Permission.User');
      expect(captured.single['username'], '"admin"');
      expect(captured.single['perm'], '"rw"');
    });

    test(
        'deleteUserPermission: username + uid as a BARE int '
        '(verified against Revoke Share*.har)', () async {
      final (svc, captured) = makeService({});
      await svc.deleteUserPermission(
          noteId: 'N1', username: 'admin', uid: '1024');
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Permission.User');
      expect(body['method'], 'delete');
      expect(body['username'], '"admin"');
      expect(body['uid'], '1024'); // bare number, not quoted
    });

    test(
        'deleteGroupPermission: UNVERIFIED shape, built by symmetry with '
        'deleteUserPermission (groupname + gid as a bare int) — pins the '
        'current guess so a future capture can confirm or correct it',
        () async {
      final (svc, captured) = makeService({});
      await svc.deleteGroupPermission(
          noteId: 'N1', groupName: 'administrators', gid: '101');
      final body = captured.single;
      expect(body['api'], 'SYNO.NoteStation.Permission.Group');
      expect(body['method'], 'delete');
      expect(body['groupname'], '"administrators"');
      expect(body['gid'], '101'); // bare number, mirroring uid
    });

    test('searchSharePriv: query param, parses user/group results', () async {
      final (svc, captured) = makeService({
        'list': [
          {'name': 'admin', 'type': 'user'},
          {'name': 'administrators', 'type': 'group'},
        ]
      });
      final results = await svc.searchSharePriv('ad');
      expect(captured.single['query'], '"ad"');
      expect(results.map((r) => r.type), ['user', 'group']);
    });
  });

  group('Server-side NSX export/import job', () {
    test('startNotebookExport: null notebookId sends literal JSON null',
        () async {
      final (svc, captured) = makeService({'task_id': 'job1'});
      await svc.startNotebookExport(destPath: '/Downloads');
      final body = captured.single;
      expect(body['object_id'], 'null'); // literal, not omitted
      expect(body['dest'], '"/Downloads"');
      expect(body['export_todo'], 'true');
    });

    test('startNotebookImport: file is an array of {name,format,path}',
        () async {
      final (svc, captured) = makeService({'task_id': 'job2'});
      await svc.startNotebookImport(
          fileName: 'a.nsx', nasPath: '/Downloads/a.nsx');
      final file = jsonDecode(captured.single['file']!) as List;
      expect(file.single, {
        'name': 'a.nsx',
        'format': 'ds',
        'path': '/Downloads/a.nsx',
      });
    });

    test('getNotebookExportStatus/getNotebookImportStatus parse progress',
        () async {
      final (svc, _) = makeService({
        'finish': true,
        'data': {'current': 9, 'total': 9},
      });
      final status = await svc.getNotebookExportStatus();
      expect(status.finished, isTrue);
      expect(status.current, 9);
      expect(status.total, 9);
    });
  });
}
