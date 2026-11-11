import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synologynotesenhanceds_enhanced/core/api/api_exception.dart';
import 'package:synologynotesenhanceds_enhanced/core/api/nas_address.dart';
import 'package:synologynotesenhanceds_enhanced/core/api/synology_api_client.dart';

Map<String, String> _form(String body) => Uri(query: body).queryParameters;

const _ok = '{"success":true,"data":{}}';

void main() {
  setUp(() => SynologyApiClient.lastReachableBaseUrl = null);

  group('NasAddress.parse', () {
    NasAddress? parse(String s, {bool https = false, int port = 5000}) =>
        NasAddress.parse(s, defaultHttps: https, defaultPort: port);

    test('bare host uses form defaults', () {
      final a = parse('192.168.0.42')!;
      expect(a.baseUrl, 'http://192.168.0.42:5000');
    });

    test('pasted https URL with port and trailing slash', () {
      final a = parse(' https://mynas.synology.me:5001/ ')!;
      expect((a.host, a.port, a.useHttps), ('mynas.synology.me', 5001, true));
    });

    test('scheme without port switches DSM default port', () {
      expect(parse('https://mynas.synology.me')!.port, 5001);
      expect(parse('http://nas', https: true, port: 5001)!.port, 5000);
    });

    test('host:port without scheme keeps toggle scheme', () {
      final a = parse('mynas.synology.me:5443', https: true, port: 5001)!;
      expect(a.baseUrl, 'https://mynas.synology.me:5443');
    });

    test('IPv6 literal is bracketed in baseUrl', () {
      expect(parse('[fd00::2]', https: true, port: 5001)!.baseUrl,
          'https://[fd00::2]:5001');
    });

    test('rejects junk', () {
      expect(parse(''), isNull);
      expect(parse('ftp://nas'), isNull);
      expect(parse('http://'), isNull);
    });
  });

  group('SynologyApiClient failover', () {
    test('connection failure on primary falls over to alternate and sticks',
        () async {
      final hosts = <String>[];
      final mock = MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == '192.168.0.42') {
          throw const SocketException('HTTP connection timed out');
        }
        return http.Response(_ok, 200);
      });
      final client = SynologyApiClient.withSid('https://192.168.0.42:5001', 'S',
          fallbackBaseUrls: ['https://nas.example.com:5001'], httpClient: mock);

      await client.call(api: 'SYNO.NoteStation.Note', version: 1, method: 'list');
      expect(hosts, ['192.168.0.42', 'nas.example.com']);
      expect(client.baseUrl, 'https://nas.example.com:5001');

      // A second (even brand-new) client goes straight to the working address.
      hosts.clear();
      final client2 = SynologyApiClient.withSid('https://192.168.0.42:5001', 'S',
          fallbackBaseUrls: ['https://nas.example.com:5001'], httpClient: mock);
      await client2.call(api: 'SYNO.NoteStation.Note', version: 1, method: 'list');
      expect(hosts, ['nas.example.com']);
    });

    test('non-connect failures are not retried elsewhere (no double writes)',
        () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        throw const SocketException('Connection reset by peer',
            osError: OSError('Connection reset by peer', 54));
      });
      final client = SynologyApiClient.withSid('https://a:5001', 'S',
          fallbackBaseUrls: ['https://b:5001'], httpClient: mock);
      await expectLater(
          client.call(api: 'SYNO.NoteStation.Note', version: 1, method: 'set'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', -1)));
      expect(calls, 1);
    });

    test('all addresses unreachable → network ApiException', () async {
      final mock = MockClient((req) async =>
          throw const SocketException('Failed host lookup: x'));
      final client = SynologyApiClient('https://a:5001',
          fallbackBaseUrls: ['https://b:5001'], httpClient: mock);
      await expectLater(client.authTypes(account: 'u'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', -1)));
    });
  });

  group('SynologyApiClient re-login', () {
    test('119 triggers re-login and the request is retried with the new SID',
        () async {
      final sids = <String?>[];
      final mock = MockClient((req) async {
        final sid = _form(req.body)['_sid'];
        sids.add(sid);
        if (sid == 'OLD') {
          return http.Response('{"success":false,"error":{"code":119}}', 200);
        }
        return http.Response(_ok, 200);
      });
      String? staleSeen;
      final client = SynologyApiClient.withSid('https://nas:5001', 'OLD',
          httpClient: mock, onSessionExpired: (stale) async {
        staleSeen = stale;
        return (sid: 'NEW', synoToken: 'T2');
      });

      await client.callCore(api: 'SYNO.FileStation.List', version: 2, method: 'list_share');
      expect(staleSeen, 'OLD');
      expect(sids, ['OLD', 'NEW']);
      expect(client.sid, 'NEW');
      expect(client.synoToken, 'T2');
    });

    test('105 probes NoteStation.Info; 119 there → re-login + retry', () async {
      final apis = <String>[];
      final mock = MockClient((req) async {
        final f = _form(req.body);
        apis.add('${f['api']}:${f['_sid']}');
        if (f['_sid'] == 'OLD') {
          final code = f['api'] == 'SYNO.NoteStation.Info' ? 119 : 105;
          return http.Response(
              '{"success":false,"error":{"code":$code}}', 200);
        }
        return http.Response(_ok, 200);
      });
      final client = SynologyApiClient.withSid('https://nas:5001', 'OLD',
          httpClient: mock,
          onSessionExpired: (_) async => (sid: 'NEW', synoToken: null));

      await client.call(api: 'SYNO.NoteStation.Notebook', version: 1, method: 'list');
      expect(apis, [
        'SYNO.NoteStation.Notebook:OLD',
        'SYNO.NoteStation.Info:OLD',
        'SYNO.NoteStation.Notebook:NEW',
      ]);
    });

    test('genuine 105 (session probe succeeds) is surfaced, no re-login',
        () async {
      var reauthCalls = 0;
      final mock = MockClient((req) async {
        final f = _form(req.body);
        if (f['api'] == 'SYNO.NoteStation.Info') return http.Response(_ok, 200);
        return http.Response('{"success":false,"error":{"code":105}}', 200);
      });
      final client = SynologyApiClient.withSid('https://nas:5001', 'S',
          httpClient: mock, onSessionExpired: (_) async {
        reauthCalls++;
        return (sid: 'NEW', synoToken: null);
      });

      await expectLater(
          client.call(api: 'SYNO.NoteStation.Note', version: 1, method: 'get'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 105)));
      expect(reauthCalls, 0);
    });

    test('failed re-login surfaces the original error', () async {
      final mock = MockClient((req) async =>
          http.Response('{"success":false,"error":{"code":106}}', 200));
      final client = SynologyApiClient.withSid('https://nas:5001', 'S',
          httpClient: mock, onSessionExpired: (_) async => null);
      await expectLater(
          client.call(api: 'SYNO.NoteStation.Note', version: 1, method: 'list'),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 106)));
    });

    test('login never triggers re-login; logout neither', () async {
      var reauthCalls = 0;
      final mock = MockClient((req) async =>
          http.Response('{"success":false,"error":{"code":119}}', 200));
      final client = SynologyApiClient.withSid('https://nas:5001', 'S',
          httpClient: mock, onSessionExpired: (_) async {
        reauthCalls++;
        return (sid: 'N', synoToken: null);
      });
      await expectLater(client.logout(), throwsA(isA<ApiException>()));
      await expectLater(client.login(account: 'a', passwd: 'p'),
          throwsA(isA<ApiException>()));
      expect(reauthCalls, 0);
    });

    test('login with rememberDevice requests a device token and stores did',
        () async {
      final bodies = <Map<String, String>>[];
      final mock = MockClient((req) async {
        bodies.add(_form(req.body));
        return http.Response(
            '{"success":true,"data":{"sid":"S","did":"DEV1"}}', 200);
      });
      final client = SynologyApiClient('https://nas:5001', httpClient: mock);
      await client.login(
          account: 'a', passwd: 'p', otpCode: '123456', rememberDevice: true);
      expect(bodies.single['enable_device_token'], 'yes');
      expect(client.deviceId, 'DEV1');

      await client.login(account: 'a', passwd: 'p', deviceId: 'DEV1');
      expect(bodies.last['device_id'], 'DEV1');
      expect(bodies.last.containsKey('otp_code'), isFalse);
    });
  });
}
