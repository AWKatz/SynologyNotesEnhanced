import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synologynotesenhanceds_enhanced/core/api/synology_api_client.dart';
import 'package:synologynotesenhanceds_enhanced/core/services/note_station_service.dart';

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
}
