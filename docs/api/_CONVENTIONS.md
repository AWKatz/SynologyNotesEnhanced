# Request conventions — resolve before mapping further

## ⚠️ Param value encoding (blocking question)

The one verified capture we have:

```
captures/Note.Encrypt.txt
api=SYNO.NoteStation.Note.Encrypt&method=create&version=1
  &object_id=%221026_QF644RE9V50IT7EO6BU21NUFRG%22
  &password=%2212345%22
  &duration=120
```

URL-decoded: `object_id="1026_QF644RE9V50IT7EO6BU21NUFRG"`, `password="12345"`,
`duration=120`.

So in the real client:
- **String values are wrapped in JSON double-quotes**, then form-urlencoded.
- **Numbers are bare** (`duration=120`, no quotes).

But our current code (`note_station_service.dart`) sends bare strings, e.g.
`note_id: noteId`.

**RESOLVED (read `synology_api_client.dart:74-91`):** the client builds a
`Map<String,String>` and hands it to `http.post(body:)`, which form-encodes values
**bare** — no JSON quoting. So we are in case #2:

- Current CRUD works only because entry.cgi tolerates bare scalar IDs.
- It **will break** for any param whose value is a JSON array/object/bool — which the
  upcoming APIs need (Smart criteria, permission lists, Todo `attr`, batch `compound`).

### ✅ IMPLEMENTED (2026-06-21)

Done in `synology_api_client.dart` — `call()` now takes `Map<String,dynamic>` and
`_encodeParams()` applies the rules below. Auth (`login`/`logout`) deliberately stays bare
(SYNO.API.Auth has no `requestFormat: JSON`). Existing service calls migrated to logical
types. Regression test: `test/synology_api_client_test.dart` pins the wire format against
the `Note.Encrypt` capture.

### Fix spec (for reference)

Change `call()` to accept `Map<String, dynamic>` and JSON-encode each value the way the
stock client does:

- `String`  → `jsonEncode(v)`  → `"..."`
- `num`     → bare (`120`)
- `bool`    → `true` / `false`
- `List`/`Map` → `jsonEncode(v)` → `["a","b"]` / `{...}`
- reserved keys (`api`, `method`, `version`, `_sid`) stay bare.

Every spec below writes params in **logical** form (`note_id = <id>`, `tag = [id1,id2]`)
and assumes the client applies this encoding. This unblocks all P1–P4 mapping.

## ⚠️ CSRF token (X-SYNO-TOKEN) — likely needed for writes

Verified in `captures/Sync.Entry.Request.txt`: every POST from the web client carries
`X-SYNO-TOKEN: <token>` (a short opaque CSRF token), and GET downloads carry the same value as
a `SynoToken` query param. There's also an incrementing `X-SYNO-HASH` header.

Reads in this capture still succeeded with our cookie/_sid style, but **DSM commonly
rejects state-changing calls (create/update/delete) without the SynoToken**. Our client
(`synology_api_client.dart`) does NOT send it yet.

**Where does the token come from?** The web UI gets it at desktop login
(`SYNO.API.Auth` login can return a `synotoken` when `enable_syno_token=yes`, or it's in
the desktop bootstrap). **Capture a login** to confirm our flow can obtain it. Until then,
writes may work via `_sid` alone on some DSM configs but fail on others (403 / error 105).

Action: add optional `synoToken` to the client; send as `X-SYNO-TOKEN` header on POST and
`SynoToken` param on GET when present. Resolve the source via a login capture.

## Known-good facts

- Endpoint: `POST /webapi/entry.cgi`, body = `application/x-www-form-urlencoded`.
- Always include `_sid` (from login). Web UI also rides a session cookie.
- IDs: `<volumeId>_<ULID>`, e.g. `1026_QF644RE9V50IT7EO6BU21NUFRG`.
- Encrypt returns a short-lived `token` used for subsequent reads of that object.
- Multi-value params (tags) are comma-joined: `tag=id1,id2` (per existing Note code).
- Responses: `{"success":true,"data":{...}}` or `{"success":false,"error":{"code":N}}`.
