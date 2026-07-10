# SYNO.Entry.Request

Versions: 1–2 · Status: ✅ verified (capture) · Feature: batch / compound calls

Runs several entry.cgi calls in ONE request. The web client uses it for startup "sync":
load notebooks + notes + tags + shortcuts + todos + smart in a single round-trip.

## Method: `request` (v1)
Params:
- `mode` = `"sequential"` (string, JSON-quoted) — also likely `"parallel"`.
- `stop_when_error` = `false` (bare bool) — if true, a failing sub-call aborts the rest.
- `compound` = JSON array of sub-requests, each `{api, method, version, ...extraParams}`.
  Extra params (e.g. `filter`, `field`) ride inside the sub-request object.

## Response
```
{ "success": true,
  "data": {
    "has_fail": false,
    "result": [ { "api","method","version","success", "data": {...} }, ... ] } }
```
`result[i]` corresponds positionally to `compound[i]`; each carries its own `success`.

## Verified example
See `captures/Sync.Entry.Request.txt` §1.

## Dart shape (planned)
```dart
Future<List<Map<String,dynamic>>> batch(
  List<Map<String,dynamic>> compound, {bool stopWhenError = false});
// returns the per-call data maps in order; caller indexes/casts each.
```
Encoding note: with the central `_encodeParams` fix, pass `mode`/`compound` as real
String/List — the client JSON-encodes them (`mode="sequential"`, `compound=[...]`).

## Use it for
- App startup (replace the N separate list calls with one batch — fewer round-trips).
- Any "load screen" that needs several lists at once.
