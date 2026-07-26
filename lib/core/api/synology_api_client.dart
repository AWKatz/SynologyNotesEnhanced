import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import 'trusted_http_client.dart';

/// Low-level HTTP client for the Synology WebAPI.
/// All calls go to /webapi/entry.cgi via POST.
class SynologyApiClient {
  // Core DSM APIs (SYNO.API.*) are registered at the root webapi dispatcher.
  static const _coreEntry = '/webapi/entry.cgi';
  // NoteStation's APIs are only registered under the package's own webapi dir
  // (verified from the stock client's requests); they 404/error at _coreEntry.
  static const _noteStationEntry = '/notestation/webapi/entry.cgi';

  final String baseUrl;
  String? _sid;
  String? _synoToken;
  final http.Client _http;

  SynologyApiClient(this.baseUrl, {http.Client? httpClient})
      : _http = httpClient ?? createTrustingClient();

  SynologyApiClient.withSid(this.baseUrl, String sid,
      {String? synoToken, http.Client? httpClient})
      : _sid = sid,
        _synoToken = synoToken,
        // Must trust self-signed / IP-mismatched DSM certs, same as the default
        // constructor — otherwise every authenticated call fails the TLS
        // handshake while login (which uses createTrustingClient) succeeds.
        _http = httpClient ?? createTrustingClient();

  String? get sid => _sid;

  /// CSRF token returned by [login] when `enable_syno_token=yes`. Sent as the
  /// `X-SYNO-TOKEN` header on authenticated POSTs and (for GET downloads) as a
  /// `SynoToken` query param. May be null on DSM configs that don't issue one.
  String? get synoToken => _synoToken;

  /// Authenticates and stores the returned SID internally.
  /// Returns the SID on success, throws [ApiException] on failure.
  Future<String> login({
    required String account,
    required String passwd,
    String session = 'NoteStation',
    String? otpCode,
  }) async {
    final data = await _call(
      api: 'SYNO.API.Auth',
      version: 7,
      method: 'login',
      params: {
        'account': account,
        'passwd': passwd,
        'session': session,
        'format': 'sid',
        // Ask DSM to issue the CSRF token alongside the SID (verified: the web
        // client sends this and gets back `synotoken`). Required for writes.
        'enable_syno_token': 'yes',
        if (otpCode != null && otpCode.isNotEmpty) 'otp_code': otpCode,
      },
      includeAuth: false,
    ) as Map<String, dynamic>;
    _sid = data['sid'] as String;
    _synoToken = data['synotoken'] as String?;
    return _sid!;
  }

  Future<List<String>> authTypes({required String account}) async {
    final result = await _call(
      api: 'SYNO.API.Auth.Type',
      version: 1,
      method: 'get',
      params: {'account': account},
      includeAuth: false,
    );
    final rows = result as List<dynamic>?;
    return rows
            ?.map((entry) => (entry as Map<String, dynamic>)['type'] as String)
            .toList() ??
        [];
  }

  Future<void> logout({String session = 'NoteStation'}) async {
    await _call(
      api: 'SYNO.API.Auth',
      version: 7,
      method: 'logout',
      params: {'session': session},
    );
    _sid = null;
    _synoToken = null;
  }

  /// Builds a download/GET URL for [api]/[method], appending the SID and CSRF
  /// token the way the web client does for attachment/thumbnail fetches
  /// (`_sid` + `SynoToken` as query params on the GET).
  Uri downloadUri({
    required String api,
    required int version,
    required String method,
    Map<String, dynamic> params = const {},
  }) {
    final query = <String, String>{
      'api': api,
      'version': version.toString(),
      'method': method,
      ..._encodeParams(params),
      if (_sid != null) '_sid': _sid!,
      if (_synoToken != null) 'SynoToken': _synoToken!,
    };
    return Uri.parse('$baseUrl$_noteStationEntry')
        .replace(queryParameters: query);
  }

  /// Builds the URL for a note's inline image attachment. VERIFIED
  /// (2026-07-25 follow-up HAR capture, entries 170 + 225): `tid` is NOT the
  /// session id (that assumption was wrong and left the image as a broken
  /// link) — it's a short-lived download ticket obtained separately via
  /// [grantDownloadTicket]. Callers must fetch one and pass it in here.
  Uri noteImageUri({
    required String linkId,
    required String ver,
    required String attachmentKey,
    required String fileName,
    required String tid,
    bool thumb = false,
  }) {
    final query = <String, String>{
      if (_synoToken != null) 'SynoToken': _synoToken!,
      'tid': tid,
      if (thumb) 'thumb': 'true',
    };
    return Uri.parse('$baseUrl/notestation/ns/dv/$linkId/$ver/$attachmentKey/$fileName')
        .replace(queryParameters: query);
  }

  /// Fetches raw bytes from [uri] using this client's own cert-trusting HTTP
  /// stack. Exists because the rich editor's WebView is a separate network
  /// stack (Chromium/WebView2) that kept failing to load inline note images
  /// directly over `https://` against this NAS's self-signed/hostname-
  /// mismatched cert — even after wiring up the WebView's own
  /// onReceivedServerTrustAuthRequest handler, sub-resource loads inside it
  /// never surfaced through any of that plugin's error callbacks either, so
  /// the failure couldn't be confirmed or fixed from there. Fetching here
  /// instead (proven to work: this is the same client every other
  /// authenticated call already succeeds through) and embedding the result
  /// as a data: URI sidesteps the WebView's networking entirely.
  Future<List<int>> fetchBytes(Uri uri) async {
    final http.Response response;
    try {
      response = await _http.get(uri);
    } catch (e) {
      throw ApiException(code: -1, message: 'Network error: $e');
    }
    if (response.statusCode != 200) {
      throw ApiException(
          code: response.statusCode, message: 'HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  /// Grants a short-lived download "ticket" (`tid`) scoped to [api]'s
  /// [methods] — VERIFIED (2026-07-25 follow-up HAR capture, entry 170):
  /// `SYNO.API.Auth.Key` `grant` (v7) with `allow_api`/`allow_methods`
  /// returns `{"tid": "..."}`, captured right before the browser's image GET
  /// that used it. Required for [noteImageUri]; the session `_sid` alone
  /// does not authenticate `ns/dv/...` downloads.
  Future<String> grantDownloadTicket({
    required String api,
    required List<String> methods,
  }) async {
    final data = await call(
      api: 'SYNO.API.Auth.Key',
      version: 7,
      method: 'grant',
      params: {'allow_api': api, 'allow_methods': methods},
    );
    return data['tid'] as String;
  }

  /// Generic call for all NoteStation APIs.
  ///
  /// Param values are JSON-encoded the way the stock Note Station web client
  /// encodes them for entry.cgi APIs declared with `requestFormat: JSON`
  /// (which every `SYNO.NoteStation.*` API is): strings/lists/maps are
  /// JSON-encoded (so a string gains surrounding quotes — `note_id="123"`),
  /// numbers and bools are sent in bare JSON form (`limit=100`, `done=true`).
  /// Pass values in their logical Dart type (String/num/bool/List/Map); null
  /// values are dropped. This is required for APIs whose params are arrays or
  /// objects (Smart criteria, permission lists, batch compound calls).
  ///
  /// Note: [SYNO.API.Auth] is intentionally NOT routed through here — it has no
  /// `requestFormat: JSON` and expects bare form fields (see [login]/[logout]).
  Future<Map<String, dynamic>> call({
    required String api,
    required int version,
    required String method,
    Map<String, dynamic>? params,
  }) async {
    final data = await _call(
      api: api,
      version: version,
      method: method,
      params: params == null ? null : _encodeParams(params),
      entryPath: _noteStationEntry,
    );
    // Write-only endpoints with nothing to report back (e.g. Notebook.delete)
    // respond `data: null` on a genuine success — not an error, and not a
    // shape any caller here actually depends on (every caller treats `data`
    // as "the fields I expect, if any"). Crashing the cast on that turned a
    // successful delete/create into a false "error" toast even though the
    // NAS had already applied it (confirmed by a subsequent sync).
    if (data == null) return {};
    return data as Map<String, dynamic>;
  }

  /// Uploads a file as part of a NoteStation `Note.set` call — VERIFIED
  /// (2026-07-25 HAR capture): unlike a typical file-upload API, NoteStation
  /// attaches images to a note by sending the whole save (content, ver,
  /// object_id, ...) as `multipart/form-data` instead of the usual
  /// form-urlencoded, with the file as one extra part. [fields] is encoded
  /// through [_encodeParams] for the same JSON-quoting convention [call]
  /// uses; [fileFieldName] is the multipart part's own `name` (the capture
  /// used the filename itself, not a fixed field like "file" — kept
  /// parameterized here in case that turns out to matter).
  ///
  /// CONFIRMED (re-checked against the raw 2026-07-25 HAR capture after a
  /// live "Failed to upload the file" / error 108 report): the browser
  /// places `api`/`version`/`method` on the request's URL query string, not
  /// in the multipart body — unlike every other call here, which sends them
  /// as `_call` form fields. Matched here now. `_sid` still goes in the form
  /// body (as it already does successfully for every other authenticated
  /// call), since the captured request instead relied on a session cookie
  /// this app doesn't carry — an `X-SYNO-HASH` header was also present with
  /// no captured explanation of how it's derived; if uploads still fail
  /// after this fix, that header is the next thing to investigate.
  Future<Map<String, dynamic>> callMultipart({
    required String api,
    required int version,
    required String method,
    required Map<String, dynamic> fields,
    required String fileFieldName,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final uri = Uri.parse('$baseUrl$_noteStationEntry').replace(
      queryParameters: {
        'api': api,
        'version': version.toString(),
        'method': method,
      },
    );
    final request = http.MultipartRequest('POST', uri);
    if (_sid != null) request.fields['_sid'] = _sid!;
    if (_synoToken != null) request.headers['X-SYNO-TOKEN'] = _synoToken!;
    request.fields.addAll(_encodeParams(fields));
    request.files.add(http.MultipartFile.fromBytes(fileFieldName, fileBytes,
        filename: fileName));

    final http.Response response;
    try {
      final streamed = await _http.send(request);
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw ApiException(code: -1, message: 'Network error: $e');
    }

    final data = _parseResponse(response);
    if (data == null) return {};
    return data as Map<String, dynamic>;
  }

  /// JSON-encodes param values per the requestFormat=JSON convention above.
  static Map<String, String> _encodeParams(Map<String, dynamic> params) {
    final encoded = <String, String>{};
    params.forEach((key, value) {
      if (value == null) return;
      if (value is num) {
        encoded[key] = value.toString();
      } else if (value is bool) {
        encoded[key] = value ? 'true' : 'false';
      } else {
        // String, List, Map, and anything else → JSON literal.
        encoded[key] = jsonEncode(value);
      }
    });
    return encoded;
  }

  Future<dynamic> _call({
    required String api,
    required int version,
    required String method,
    Map<String, String>? params,
    bool includeAuth = true,
    String entryPath = _coreEntry,
  }) async {
    final body = <String, String>{
      'api': api,
      'version': version.toString(),
      'method': method,
      ...?params,
    };

    final headers = {'Content-Type': 'application/x-www-form-urlencoded'};

    if (includeAuth && _sid != null) {
      body['_sid'] = _sid!;
      // CSRF protection: the web client sends the token as a header on every
      // authenticated POST. Without it, writes can 403 on some DSM configs.
      if (_synoToken != null) headers['X-SYNO-TOKEN'] = _synoToken!;
    }

    final http.Response response;
    try {
      response = await _http.post(
        Uri.parse('$baseUrl$entryPath'),
        headers: headers,
        body: body,
      );
    } catch (e) {
      throw ApiException(code: -1, message: 'Network error: $e');
    }

    return _parseResponse(response);
  }

  /// Shared response handling for [_call] and [callMultipart]: HTTP status,
  /// the `success` envelope, and unwrapping `data`.
  dynamic _parseResponse(http.Response response) {
    if (response.statusCode != 200) {
      throw ApiException(
        code: response.statusCode,
        message: 'HTTP ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      final errorMap = json['error'] as Map<String, dynamic>?;
      final code = errorMap?['code'] as int? ?? -1;
      throw ApiException(code: code, message: ApiException.describe(code));
    }

    return json['data'];
  }
}
