import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synologynotesenhanceds_enhanced/core/api/synology_api_client.dart';

/// Parses an `application/x-www-form-urlencoded` body into a map.
Map<String, String> _form(String body) =>
    Uri(query: body).queryParameters;

void main() {
  group('SynologyApiClient param encoding', () {
    /// Builds a client whose mock transport captures the last request body and
    /// returns a generic success envelope.
    (SynologyApiClient, List<Map<String, String>>) makeClient() {
      final captured = <Map<String, String>>[];
      final mock = MockClient((req) async {
        captured.add(_form(req.body));
        return http.Response('{"success":true,"data":{}}', 200);
      });
      final client =
          SynologyApiClient.withSid('https://nas:5001', 'SID', httpClient: mock);
      return (client, captured);
    }

    test('strings are JSON-quoted, numbers stay bare (matches Note.Encrypt capture)',
        () async {
      final (client, captured) = makeClient();

      // Mirrors captures/Note.Encrypt.txt:
      //   object_id="1026_QF..."  password="12345"  duration=120
      await client.call(
        api: 'SYNO.NoteStation.Note.Encrypt',
        version: 1,
        method: 'create',
        params: {
          'object_id': '1026_QF644RE9V50IT7EO6BU21NUFRG',
          'password': '12345',
          'duration': 120,
        },
      );

      final body = captured.single;
      expect(body['object_id'], '"1026_QF644RE9V50IT7EO6BU21NUFRG"');
      expect(body['password'], '"12345"');
      expect(body['duration'], '120'); // bare number
      expect(body['api'], 'SYNO.NoteStation.Note.Encrypt');
      expect(body['version'], '1');
      expect(body['method'], 'create');
      expect(body['_sid'], 'SID');
    });

    test('bools are bare json, lists/maps are json-encoded, nulls dropped',
        () async {
      final (client, captured) = makeClient();

      await client.call(
        api: 'SYNO.NoteStation.Note',
        version: 4,
        method: 'list',
        params: {
          'include_content': true,
          'include_attachment': false,
          'tags': ['a', 'b'],
          'attr': {'k': 1},
          'notebook_id': null, // should be dropped
        },
      );

      final body = captured.single;
      expect(body['include_content'], 'true');
      expect(body['include_attachment'], 'false');
      expect(jsonDecode(body['tags']!), ['a', 'b']);
      expect(jsonDecode(body['attr']!), {'k': 1});
      expect(body.containsKey('notebook_id'), isFalse);
    });

    test('NoteStation calls route to /notestation/webapi, auth to /webapi',
        () async {
      final paths = <String>[];
      final mock = MockClient((req) async {
        paths.add(req.url.path);
        if (_form(req.body)['method'] == 'login') {
          return http.Response('{"success":true,"data":{"sid":"S"}}', 200);
        }
        return http.Response('{"success":true,"data":{}}', 200);
      });
      final client = SynologyApiClient('https://nas:5001', httpClient: mock);

      await client.login(account: 'A', passwd: 'p');
      await client.call(
          api: 'SYNO.NoteStation.Note', version: 3, method: 'list');

      expect(paths[0], '/webapi/entry.cgi'); // auth
      expect(paths[1], '/notestation/webapi/entry.cgi'); // NoteStation
    });

    test('downloadUri targets /notestation/webapi/entry.cgi', () {
      final client = SynologyApiClient.withSid('https://nas:5001', 'SID');
      final uri = client.downloadUri(
          api: 'SYNO.NoteStation.Note', version: 3, method: 'download');
      expect(uri.path, '/notestation/webapi/entry.cgi');
    });

    test('login requests syno token, stores it, and sends X-SYNO-TOKEN on writes',
        () async {
      final bodies = <Map<String, String>>[];
      final headers = <Map<String, String>>[];
      final mock = MockClient((req) async {
        bodies.add(_form(req.body));
        headers.add(req.headers);
        if (_form(req.body)['method'] == 'login') {
          return http.Response(
              '{"success":true,"data":{"sid":"SID","synotoken":"TOK.123"}}', 200);
        }
        return http.Response('{"success":true,"data":{}}', 200);
      });
      final client = SynologyApiClient('https://nas:5001', httpClient: mock);

      await client.login(account: 'Aaron', passwd: 'pw');
      expect(bodies.first['enable_syno_token'], 'yes');
      expect(client.synoToken, 'TOK.123');

      // A subsequent authenticated write must carry the CSRF header.
      await client.call(
          api: 'SYNO.NoteStation.Note', version: 3, method: 'set');
      expect(headers.last['X-SYNO-TOKEN'], 'TOK.123');
    });

    test('withSid carries a synoToken into request headers', () async {
      final headers = <Map<String, String>>[];
      final mock = MockClient((req) async {
        headers.add(req.headers);
        return http.Response('{"success":true,"data":{}}', 200);
      });
      final client = SynologyApiClient.withSid('https://nas:5001', 'SID',
          synoToken: 'TOK.9', httpClient: mock);

      await client.call(
          api: 'SYNO.NoteStation.Note', version: 3, method: 'list');
      expect(headers.single['X-SYNO-TOKEN'], 'TOK.9');
    });

    test(
        'noteImageUri targets ns/dv with SynoToken + the given tid (not _sid) '
        '(verified via HAR capture)', () {
      final client = SynologyApiClient.withSid('https://nas:5001', 'SID',
          synoToken: 'TOK.9');
      final uri = client.noteImageUri(
        linkId: 'L1',
        ver: 'V1',
        attachmentKey: 'A1',
        fileName: 'photo.png',
        tid: 'TICKET.1',
      );
      expect(uri.path, '/notestation/ns/dv/L1/V1/A1/photo.png');
      expect(uri.queryParameters['tid'], 'TICKET.1');
      expect(uri.queryParameters['SynoToken'], 'TOK.9');
      expect(uri.queryParameters.containsKey('_sid'), isFalse);
    });

    test(
        'grantDownloadTicket calls SYNO.API.Auth.Key grant and returns the tid '
        '(verified via HAR capture)', () async {
      final bodies = <Map<String, String>>[];
      final mock = MockClient((req) async {
        bodies.add(_form(req.body));
        return http.Response(
            '{"success":true,"data":{"tid":"TICKET.1"}}', 200);
      });
      final client = SynologyApiClient.withSid('https://nas:5001', 'SID',
          httpClient: mock);

      final tid = await client.grantDownloadTicket(
        api: 'SYNO.NoteStation.Note',
        methods: ['download'],
      );

      expect(tid, 'TICKET.1');
      final body = bodies.single;
      expect(body['api'], 'SYNO.API.Auth.Key');
      expect(body['version'], '7');
      expect(body['method'], 'grant');
      expect(body['allow_api'], '"SYNO.NoteStation.Note"');
      expect(body['allow_methods'], '["download"]');
    });

    test('downloadUri appends _sid and SynoToken as query params', () {
      final client = SynologyApiClient.withSid('https://nas:5001', 'SID',
          synoToken: 'TOK.9');
      final uri = client.downloadUri(
        api: 'SYNO.NoteStation.Note',
        version: 3,
        method: 'download',
        params: {'object_id': 'N1', 'file_id': 'thumb'},
      );
      expect(uri.queryParameters['_sid'], 'SID');
      expect(uri.queryParameters['SynoToken'], 'TOK.9');
      expect(uri.queryParameters['object_id'], '"N1"');
      expect(uri.path, '/notestation/webapi/entry.cgi');
    });

    test('no synoToken → no X-SYNO-TOKEN header (graceful on older DSM)',
        () async {
      final headers = <Map<String, String>>[];
      final mock = MockClient((req) async {
        headers.add(req.headers);
        return http.Response('{"success":true,"data":{}}', 200);
      });
      final client =
          SynologyApiClient.withSid('https://nas:5001', 'SID', httpClient: mock);
      await client.call(
          api: 'SYNO.NoteStation.Note', version: 3, method: 'list');
      expect(headers.single.containsKey('X-SYNO-TOKEN'), isFalse);
    });

    test(
        'call() treats a null `data` (e.g. Notebook.delete\'s response) as '
        'success, not a crash', () async {
      final mock = MockClient((req) async {
        // No `data` key at all — same shape DSM sends back for delete-style
        // endpoints with nothing to report. Previously crashed the
        // `as Map<String, dynamic>` cast with a real success response,
        // surfacing as a false "error" toast for an operation that had
        // already succeeded server-side.
        return http.Response('{"success":true}', 200);
      });
      final client =
          SynologyApiClient.withSid('https://nas:5001', 'SID', httpClient: mock);

      final data = await client.call(
        api: 'SYNO.NoteStation.Notebook',
        version: 2,
        method: 'delete',
        params: {'object_id': 'N1'},
      );

      expect(data, <String, dynamic>{});
    });

    test('callMultipart sends the file + fields and parses the success envelope',
        () async {
      String? capturedContentType;
      Uri? capturedUrl;
      String? capturedBody;
      final mock = MockClient((req) async {
        capturedContentType = req.headers['content-type'];
        capturedUrl = req.url;
        capturedBody = req.body;
        return http.Response(
          '{"success":true,"data":{"data":[{"object_id":"N1","ver":"v2"}]}}',
          200,
        );
      });
      final client = SynologyApiClient.withSid('https://nas:5001', 'SID',
          synoToken: 'TOK.1', httpClient: mock);

      final result = await client.callMultipart(
        api: 'SYNO.NoteStation.Note',
        version: 3,
        method: 'set',
        fields: {'object_id': 'N1', 'ver': 'v1', 'content': '<div></div>'},
        fileFieldName: 'photo.png',
        fileBytes: [1, 2, 3, 4],
        fileName: 'photo.png',
      );

      expect(capturedContentType, contains('multipart/form-data'));
      // Matches the real captured browser request: api/version/method on
      // the URL query string, not as multipart form fields (unlike every
      // other call, which sends them as form-urlencoded body fields).
      expect(capturedUrl?.queryParameters['api'], 'SYNO.NoteStation.Note');
      expect(capturedUrl?.queryParameters['version'], '3');
      expect(capturedUrl?.queryParameters['method'], 'set');
      expect(capturedBody, isNot(contains('name="api"')));
      expect(capturedBody, contains('name="_sid"'));
      expect((result['data'] as List).first['ver'], 'v2');
    });

    test('authTypes sends SYNO.API.Auth.Type and parses returned type list',
        () async {
      final captured = <Map<String, String>>[];
      final mock = MockClient((req) async {
        captured.add(_form(req.body));
        return http.Response(
          '{"success":true,"data":[{"type":"passwd"},{"type":"otp"}]}',
          200,
        );
      });
      final client = SynologyApiClient('https://nas:5001', httpClient: mock);

      final types = await client.authTypes(account: 'Aaron');

      expect(types, ['passwd', 'otp']);
      final body = captured.single;
      expect(body['api'], 'SYNO.API.Auth.Type');
      expect(body['version'], '1');
      expect(body['method'], 'get');
      expect(body['account'], 'Aaron');
      expect(body.containsKey('_sid'), isFalse);
    });
  });
}
