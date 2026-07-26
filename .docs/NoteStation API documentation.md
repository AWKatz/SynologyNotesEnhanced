# NoteStation API Documentation

Synology never published a spec for `SYNO.NoteStation.*` — this document is the
reverse-engineered result of capturing real traffic between the stock Note Station web
client and a live DSM NAS. It is the single source of truth for every NoteStation API this
project uses or plans to use, superseding the previously-scattered `README.md` /
`NoteStation-schemas.md` / `SYNO.*.md` / `_CONVENTIONS.md` files in this folder.

It backs the Dart service layer at `lib/core/services/note_station_service.dart` and
`lib/core/api/synology_api_client.dart`.

**Visibility note:** this file is the one piece of `.docs/` that's tracked in git and shipped
publicly. Everything else this file references (`CAPTURE-CHECKLIST.md`, `captures/*.txt`,
`captures/*.har`) is kept locally as private working material — real NAS traffic, even when
redacted, isn't shipped by default — so those paths won't resolve in a fresh clone. If you're
contributing a new capture, open an issue/PR and paste the redacted request/response rather
than expecting these paths to exist for you.

## How this was derived — trust levels

Every fact below is tagged with how it was learned, in order of trust:

1. **V — live capture.** Stock Note Station web UI + browser DevTools → Network tab → the
   `entry.cgi` request body and response, captured as a HAR or manually transcribed. Ground
   truth. Raw evidence lives in `captures/*.txt` and `captures/*.har`.
2. **JS — web UI source.** Grepped from the minified NoteStation JS bundle. Reliable but not
   independently exercised.
3. **I — inference.** Derived by pattern-matching against APIs that *are* verified (e.g.
   assuming `Notebook.delete` looks like the verified `Note.delete`). **Must be verified by
   capture before depending on it for anything destructive or hard to undo.**

To add a new capture: open DevTools → Network, filter `entry.cgi`, tick "Preserve log",
perform one action at a time, and save the decoded request + response. See
`CAPTURE-CHECKLIST.md` for the specific click-by-click list of what's still needed and in
what order — that file is the *process* doc; this one is the *reference*.

---

## Transport & wire conventions

### Endpoints

- Core DSM APIs (`SYNO.API.*`) — `POST /webapi/entry.cgi`
- NoteStation APIs (`SYNO.NoteStation.*`) — `POST /notestation/webapi/entry.cgi`
  (they 404/error at the core endpoint — verified: the stock client always uses the
  package-local path for these)
- Both are `application/x-www-form-urlencoded` POST bodies.
- Attachment/thumbnail downloads are the one **GET** exception — see below.

### Common params on every call

`api`, `method`, `version`, and (once logged in) `_sid`.

### Param value encoding — V

Every `SYNO.NoteStation.*` API is declared client-side with `requestFormat: JSON`, which
changes how param values are form-encoded:

| Dart type | Wire form | Example |
|---|---|---|
| `String` | JSON-quoted | `title="New note"` |
| `num` | bare | `duration=120` |
| `bool` | bare JSON | `recycle=true` |
| `List` / `Map` | JSON-encoded | `tag=["A","B"]`, `filter={"recycle":false}` |
| `null` | omitted entirely | — |

Verified against `captures/Note.Encrypt.txt`:
```
object_id=%221026_QF644RE9V50IT7EO6BU21NUFRG%22   → object_id="1026_QF644RE9V50IT7EO6BU21NUFRG"
password=%2212345%22                               → password="12345"
duration=120                                        → bare number
```

`SYNO.API.Auth` is the one exception — it has no `requestFormat: JSON` and takes bare form
fields (`account=foo`, not `account="foo"`).

Implemented in `synology_api_client.dart`'s `_encodeParams()`; pinned by
`test/synology_api_client_test.dart` against the Note.Encrypt capture.

### Authentication & CSRF — V

1. `SYNO.API.Auth` `login` (v7) with `enable_syno_token=yes` returns both `sid` and
   `synotoken` in the response.
2. `sid` rides as `_sid` on every subsequent call (form param on POST, query param on GET).
3. `synotoken` is sent as the `X-SYNO-TOKEN` **header** on every authenticated POST, and as
   a `SynoToken` **query param** on GET downloads. Verified in
   `captures/Sync.Entry.Request.txt` — every POST from the web client carries it, plus an
   incrementing `X-SYNO-HASH` header (purpose not yet investigated — not required for
   writes to succeed, so not implemented).
4. Without the CSRF token, reads may still succeed on some DSM configs but writes commonly
   403 / error 105. Always send it once available.

### Response envelope & errors — V

```json
{ "success": true, "data": { ... } }
{ "success": false, "error": { "code": 119 } }
```

`ApiException` in `lib/core/api/api_exception.dart` maps known error codes to messages.

### Object IDs — V

`<volumeId>_<ULID>`, e.g. `1026_QF644RE9V50IT7EO6BU21NUFRG`. The id lives in the **response
field** (`object_id`) for API calls, but in the **entry filename** (not a JSON field) inside
a `.nsx` export — see the .nsx section below.

The addressing param name varies by API family — confirm per API:
- `object_id` — Note, Notebook, Note.Encrypt (all verified)
- `note_id` / `notebook_id` — only seen in older/mock code, not in any real capture

---

## Coverage status

Legend: ✅ done · 📝 spec mapped, needs a capture to verify · 🔲 not started
Confidence: **V** live capture · **I** inference
**In app?** — whether this project's Dart code actually calls this API today, distinct from
whether it's been capture-verified. Several APIs below are verified but not (yet) wired in.

| API | Versions | Status | Conf | In app? | Feature |
|---|---|---|---|---|---|
| SYNO.API.Auth | 7 | ✅ | V | ✅ | Login/logout, CSRF token issuance |
| SYNO.API.Auth.Type | 1 | ✅ | V | ✅ | 2FA/OTP type discovery |
| SYNO.API.Auth.Key | 7 | ✅ | V | ✅ | Grants a short-lived download ticket (`tid`) |
| SYNO.Entry.Request | 1-2 | ✅ | V | — | Batch/compound calls (startup sync) — verified but the service layer still issues separate list calls |
| SYNO.NoteStation.Stack | 1 | ✅ | V | ✅ | Shelves (list only) |
| SYNO.NoteStation.Notebook | 1-2 | ✅ | V | ✅ | Notebooks (list/create/rename/delete) |
| SYNO.NoteStation.Note | 1-4 | ✅ | V | ✅ | Notes: list/get/create/set/delete(trash)/copy |
| SYNO.NoteStation.Note `set` (multipart) | 3 | ✅ | V | ✅ | Attachment/image upload — see below, not a separate FileStation API |
| Inline image/attachment `ns/dv/` URL | — | ✅ | V | ✅ | Ticket-gated static fetch — see below; supersedes the `method=download` GET this doc used to describe as the only path (that builder still exists in code but nothing calls it) |
| SYNO.NoteStation.Note.Encrypt | 1 | ✅ | V | ✅ | Set/change password, unlock-session token |
| SYNO.NoteStation.Tag | 1-2 | ✅ | V | ✅ | Tags (list/create) |
| SYNO.NoteStation.FTS | 1 | ✅ | V | ✅ | Full-text search |
| SYNO.NoteStation.Shortcut | 1 | ✅ | V | — | Sidebar shortcuts — verified but not read/written by this project |
| SYNO.Core.UserSettings | 1 | ✅ | V | — | View/sort/todo-filter prefs — verified but this project keeps these local instead |
| SYNO.NoteStation.Todo | 1-2 | 📝 | V* | — | Envelope verified, empty — no item shape yet |
| SYNO.NoteStation.Smart | 1 | 📝 | V* | — | Envelope verified, empty — no shape yet |
| SYNO.NoteStation.Note.Polling | 1-3 | 📝 | I | — | Incremental sync — not captured |
| SYNO.NoteStation.Notebook.Polling | 1 | 📝 | I | — | Incremental sync — not captured |
| SYNO.NoteStation.Note.Version | 1-2 | 🔲 | I | — | Version history |
| SYNO.API.Encryption | 1 | 🔲 | I | — | RSA-wrapped passwords (if used) |
| SYNO.NoteStation.Share.Priv | 1-2 | 🔲 | I | — | Sharing |
| SYNO.NoteStation.Shard / Shard.Link | 1 | 🔲 | I | — | Public share links |
| SYNO.NoteStation.Permission* | 1 | 🔲 | I | — | Root/user/group/public perms |
| SYNO.NoteStation.Export.* | 1 | 🔲 | I | — | Export note/.nsx/.docx |
| SYNO.NoteStation.Import.* | 1 | 🔲 | I | — | Import .nsx/.enex/Evernote |
| SYNO.NoteStation.Notebook.Preset | 1 | 🔲 | I | — | Notebook templates |
| SYNO.NoteStation.Setting / Setting.Global | 1-2 | 🔲 | I | — | User/global settings |
| SYNO.NoteStation.Info | 1-3 | 🔲 | I | — | Service info |

*"Restore from trash" and "permanently delete from trash" are **not** a separate `Ghost`
API — trash itself is `Note.delete` + `recycle=true` (verified, see below). There is no
verified restore/purge call yet.

The `SYNO.NoteStation.Import.*` row above is about a *server-side* import API and remains
unstarted — separately, this project already has a fully working *client-side* `.nsx`
**import**, decoding the ZIP bundle locally with no server API involved at all (see the
`.nsx export file format` section below; `NsxBundle.decode` in `lib/core/nsx/nsx_codec.dart`).
Don't read "Import unstarted" as "you can't get notes in from a `.nsx` file today" — you can,
it just doesn't go through DSM.

---

## Authentication APIs

### SYNO.API.Auth — v7 — V

**`login`**
```
api=SYNO.API.Auth&version=7&method=login
&session=NoteStation&enable_syno_token=yes
&account=<user>&passwd=<pass>&format=sid
&otp_code=<optional>
```
```json
{"data":{"account":"...","sid":"...","synotoken":"...","device_id":"..."},"success":true}
```
`synotoken` is only present when `enable_syno_token=yes` is sent.

**`logout`**
```
api=SYNO.API.Auth&version=7&method=logout&session=NoteStation
```

### SYNO.API.Auth.Type — v1 — V

```
api=SYNO.API.Auth.Type&version=1&method=get&account=<user>
```
Returns the list of 2FA types available for the account (used to decide whether to prompt
for an OTP code before login).

---

## Batch calls

### SYNO.Entry.Request — v1-2 — V

Runs several `entry.cgi` calls in one round-trip. The web client uses this for app
startup — one call loads notebooks + notes + tags + shortcuts + todos + smart notebooks.

```
api=SYNO.Entry.Request&method=request&version=1
&stop_when_error=false&mode="sequential"
&compound=[
  {"api":"SYNO.NoteStation.Notebook","method":"list","version":2},
  {"api":"SYNO.NoteStation.Note","method":"list","version":3,
     "filter":{"fast_result":true},"field":{"commit_msg":true}},
  {"api":"SYNO.NoteStation.Tag","method":"list","version":1},
  {"api":"SYNO.NoteStation.Shortcut","method":"list","version":1},
  {"api":"SYNO.NoteStation.Todo","method":"list","version":1},
  {"api":"SYNO.NoteStation.Smart","method":"list","version":1}
]
```
```json
{"data":{"has_fail":false,"result":[
  {"api":"SYNO.NoteStation.Notebook","method":"list","version":2,"success":true,"data":{...}},
  ...one entry per compound item, in order...
]},"success":true}
```
`result[i]` aligns positionally with `compound[i]`; each sub-result carries its own
`success`. `stop_when_error=false` means one failing sub-call doesn't abort the rest.
`mode` is also plausibly `"parallel"` (seen used for a single-call batch in the encrypt
capture) — semantics of sequential-vs-parallel beyond ordering are not yet explored.

Not currently used by the Dart service layer (which still issues separate list calls);
adopting it would cut app-startup round-trips.

---

## Core NoteStation APIs

### SYNO.NoteStation.Stack — v1 — V (Shelves)

**`list`**
```
api=SYNO.NoteStation.Stack&version=1&method=list
```
Returns `data.stacks[]`, each `{stack_id, title}`.

### SYNO.NoteStation.Notebook — v1-2 — V

**`list`** → `data.notebooks[]`, `data.total` (schema below).

**`create`**
```
api=SYNO.NoteStation.Notebook&version=2&method=create
&title="My Notebook"&stack_id=<optional shelf id>
```
Returns the new notebook under `data.notebook`.

**`update`** (rename) — object-addressed by `object_id`:
```
api=SYNO.NoteStation.Notebook&version=2&method=update
&object_id="<id>"&title="New Title"
```

**`delete`** — object-addressed by `object_id`:
```
api=SYNO.NoteStation.Notebook&version=2&method=delete&object_id="<id>"
```

### SYNO.NoteStation.Note — v1-4 — V (core CRUD)

**`list`** — v3, structured `filter`/`field` objects (not v4/order/fields-csv):
```
api=SYNO.NoteStation.Note&version=3&method=list
&filter={"recycle":false,"archive":false,"parent_id":"<optional notebook id>"}
&field={"link_id":true,"commit_msg":true}
&offset=0&limit=50&sort_by="title"&sort_direction="desc"
```
⚠️ The list response does **not** include `content` or `tag` per note — see the Note
schema note below. Filtering by `owner` (e.g. `"owner":1026`) also appears in the stock
client's requests but isn't required.

**`get`** — v3, single note, full detail including `content`:
```
api=SYNO.NoteStation.Note&version=3&method=get&object_id="<id>"
```
No `include_content`/`include_attachment` flags — content is returned by default. Optional
`&ver="<sha1>"` fetches a specific historical revision. The note object is **directly**
under `data` (not `data.note`).

**`create`** — v3. The real client creates an *empty* note, then applies body/tags via a
follow-up `set`:
```
api=SYNO.NoteStation.Note&version=3&method=create
&commit_msg={"device":"desktop","listable":false}
&title="Untitled Note"&parent_id="<notebook id>"&encrypt=false
```
Response is the new note directly under `data`, including a fresh `ver`.

**`set`** (this is "update") — v3, optimistic concurrency via `ver` + `check_conflict`:
```
api=SYNO.NoteStation.Note&version=3&method=set
&commit_msg={"device":"desktop"}
&object_id="<id>"&ver="<current sha1>"&check_conflict=true
&title="New title"            (optional)
&content="<html>"&brief="<plain-text preview derived from the html>"   (optional pair)
&tag=["TagName","OtherTag"]   (optional — JSON array of tag NAMES, not tag_ids — see Tag)
&is_starred=true              (optional)
```
`ver` is **required** for the write to be accepted; the server rejects on mismatch. The
response is a **partial** object under `data.data[0]` (not a full note), carrying the new
`ver`/`mtime`:
```json
{"data":{"data":[{"object_id":"<id>","ver":"<new sha1>","mtime":...,"link_id":...,"attachment":null,"thumb":null}]},"success":true}
```

**`delete`** (move to trash) — v3 — V, confirmed 2026-07-19:
```
api=SYNO.NoteStation.Note&version=3&method=delete
&object_id=["<id>"]&recycle=true
```
`object_id` is a **JSON array** even for a single note (batch-capable). This is a **soft**
delete — it flips the note's `recycle` flag; the object isn't removed. A subsequent `list`
with `filter:{"recycle":false,...}` no longer returns it.

Restore-from-trash and permanent purge are **not verified**. By symmetry with other boolean
fields (`is_starred` toggles via `set`), restore is *plausibly* `set` with `recycle:false`,
and listing trash is *plausibly* `list` with `filter:{"recycle":true}` — but neither has
been captured. Do not implement either on this guess; the app currently only ever trashes,
never restores or purges.

**`copy`** — v3 — V. General-purpose duplicate-with-transform, used both to encrypt a note
and (per an older capture) to decrypt one server-side during "copy without password":
```
api=SYNO.NoteStation.Note&version=3&method=copy
&commit_msg={"device":"desktop","listable":true}
&object_id="<source note id>"&ver="<source's current ver>"
&content="<new content — see Note.Encrypt below for the encrypt case>"
&brief="<plain text>"&tag=[]&title="<title>"
&source_url=""&latitude=0&longitude=0&location=""
&parent_id="<target notebook id>"
&encrypt=<bool>&recycle=false
&new_password="<plaintext password>"   (only when encrypt=true)
```
Returns a **new** note object (different `object_id` from the request's). See the
Note.Encrypt section for the full encrypt-a-note flow and an important stock-client quirk.

### Note download (attachments/thumbnails) — v3 — V — GET, not POST — ⚠️ defined, unused

```
GET /notestation/webapi/entry.cgi?api=SYNO.NoteStation.Note&method=download&version=3
  &object_id="<note id>"&format="raw"
  &md5="<attachment md5>"&file_id="<attachment ref or 'thumb'>"&filename="thumb.png"
  &SynoToken=<csrf token>
```
Returns raw bytes. `md5`/`file_id` come from the note's `thumb`/`attachment` object fields.
This URL builder (`SynologyApiClient.downloadUri`) exists in code but **nothing in the app
currently calls it** — actual inline image/attachment fetching goes through the separate
ticket-gated `ns/dv/` path documented next, discovered later and verified against a real
capture. Left here in case a future need for the plain `method=download` form comes up, but
treat it as unconfirmed against current DSM versions until it's actually exercised again.

### SYNO.API.Auth.Key — v7 — V (download tickets)

**`grant`** — mints a short-lived ticket (`tid`) scoped to one API + a list of its methods:
```
api=SYNO.API.Auth.Key&version=7&method=grant
&allow_api="SYNO.NoteStation.Note"&allow_methods=["download"]
```
```json
{"data":{"tid":"<ticket>"},"success":true}
```
The session `_sid` alone does **not** authenticate the `ns/dv/...` download path below —
`tid` is required. This project grants one ticket per session (on first image render) and
reuses it for every image in every note rather than granting a fresh one per image.

### Inline image/attachment download — `ns/dv/` — V — GET, not `entry.cgi`

```
GET /notestation/ns/dv/<link_id>/<ver>/<attachment_key>/<file_name>
  ?SynoToken=<csrf token>&tid=<ticket from Auth.Key grant>
  [&thumb=true]
```
- `link_id` — the note's `link_id` field (only present when `Note.list`/`Note.get` was
  called with `field={"link_id":true}`).
- `ver` — the note's current content revision (same `ver` used for `Note.set`'s optimistic
  concurrency).
- `attachment_key` — the key into the note's `attachment` map (NOT the same as the `ref`
  attribute embedded in the note's `<img ref="...">` HTML — the two need pairing, see
  `note_editor.dart`'s `_refToAttachmentKey`).
- `thumb=true` requests the thumbnail-sized rendition instead of the full attachment.

Not a JSON-enveloped `entry.cgi` call — returns raw bytes directly, same as the unused
`method=download` GET above, just a different URL shape entirely. Verified 2026-07-25 via a
follow-up HAR capture after the naive assumption "`tid` is just the session id" produced a
broken image link in practice.

⚠️ The rich-text WebView editor (`flutter_inappwebview`) is a separate network stack from
the rest of the app and kept failing to load `https://` images from this NAS's self-signed/
hostname-mismatched cert directly, even with the WebView's own server-trust handler wired
up. Workaround: images shown *inside the editor* are fetched as bytes through this same
ticket-gated URL using the app's own cert-trusting HTTP client, then embedded as `data:`
URIs — no WebView network request happens at all for editor-visible images. The read-only
note view (outside the editor) still points `<img src>` directly at the `ns/dv/` URL.

### Attachment upload — `Note.set` multipart (v3) — V

There is no separate upload API — attachments are added by resending `Note.set` itself as
`multipart/form-data` instead of the usual form-urlencoded body, with the file as one extra
part:
```
POST /notestation/webapi/entry.cgi?api=SYNO.NoteStation.Note&version=3&method=set
Content-Type: multipart/form-data; boundary=...

  _sid=<sid>
  commit_msg={"device":"desktop","listable":false}
  object_id="<note id>"&ver="<current sha1>"&check_conflict=true
  content="<html containing <img ref=\"...\">>"&brief="<plain text>"
  attachment=[{"action":"create","name":"<file name>","format":"raw",
               "source":"<file name>","ref":"<caller-generated ref>","rotate":true}]
  <file part, name="<file name>", the raw bytes>
```
Notable deviations from every other call in this doc: `api`/`version`/`method` ride on the
**URL query string**, not the multipart body (confirmed against a real "Failed to upload the
file" / error 108 report — the browser puts them on the URL for this call specifically); and
`X-SYNO-TOKEN` goes in a header exactly as usual. `ref` is caller-generated (the capture used
`base64(epoch_ms + filename)`) and must match the `ref` attribute already embedded in the
`<img>` tag inside `content`. The response has the same partial `data.data[0]` shape as a
normal `Note.set`, but this one also carries a fresh `link_id`/`attachment` map containing
*only* the newly-added entry — merge onto the note's existing attachment map, don't replace
it. A captured `X-SYNO-HASH` header on the real client's request has no confirmed purpose and
isn't sent here; uploads work without it, but it's the next thing to check if that changes.

### SYNO.NoteStation.Note.Encrypt — v1 — V

Client-side encryption end to end — see the dedicated section below for the crypto
algorithm. This API's own two methods are thin:

**`create`** (register a password / open an unlock session):
```
api=SYNO.NoteStation.Note.Encrypt&version=1&method=create
&object_id="<note id>"&password="<plaintext>"&duration=120
```
```json
{"data":{"token":"lZ4Xp16485yR1784486734"},"success":true}
```
`duration` is seconds the resulting `token` stays valid for. **This call does not itself
encrypt anything** — see "Encrypting a note" below for what actually changes the content.

**`check`** (validate an unlock token is still live) — seen only inside a
`SYNO.Entry.Request` batch:
```
{"api":"SYNO.NoteStation.Note.Encrypt","method":"check","version":1,
 "object_id":"<id>","token":"<token from create>"}
```
```json
{"success":true}
```

#### Encrypting a note — the full flow — V (2026-07-19 capture)

The stock client does **not** do an in-place `Note.set` to encrypt a note. It:

1. Encrypts the plaintext HTML **client-side** (see crypto section) into the `Salted__`
   envelope.
2. Submits it via **`Note.copy`** (not `set`) against the *source* note's `object_id`/`ver`,
   with `content=<encrypted blob>`, `encrypt=true`, `new_password=<plaintext>`,
   `recycle=false`, and (notably) `brief=<plain text>` — **the brief stays plaintext even
   though content is encrypted.** Never trust `brief`/excerpt as a safe preview for an
   encrypted note.
3. `Note.copy` returns a **new note object** (new `object_id`) carrying the encrypted
   content — the source note's id is different from the response's id.
4. The client then calls `Note.Encrypt` `create` against the **new** note's id with the same
   password, purely to open a 120s "already unlocked" convenience session — not required
   for the encrypted state to persist (that's set by step 2 already).

⚠️ **Stock-client quirk, confirmed independently in a second capture:** the original
plaintext note is **left behind**, untouched, as a separate object. A trash capture from
the same session showed a note titled `"NEW NOTE - Encrypt - Duplicate - Encrypt"` — i.e.
plaintext duplicates accumulating from repeated encrypt actions in the real app. **This
project's implementation deliberately does not reproduce that flaw**: after the encrypted
copy is confirmed created, the plaintext original is trashed (`Note.delete recycle=true`),
so "encrypt this note" never leaves readable plaintext sitting next to it. See
`NasNotesRepository.encryptNote` in the Dart code.

Changing the password on an already-encrypted note, and permanently removing encryption,
are **not captured** — plausibly the same copy-based pattern (decrypt or re-encrypt
client-side, submit via `copy`) but unverified. Not implemented.

### SYNO.NoteStation.Tag — v1-2 — V

**`list`** → `data.tags[]`, `data.total` (schema below — note `tag_id` is a composite
`"Name@uid"` string, not a ULID).

**`create`**
```
api=SYNO.NoteStation.Tag&version=2&method=create&name="Accounts"
```
Returns the new tag under `data.tag`.

⚠️ **Note.list never returns per-note tags.** Tag membership for a *list* of notes is only
derivable by inverting each `Tag`'s `items` array (note ids carrying that tag) — see the Note
schema note. `Note.get` (single note) *does* include a `tag` array directly.

⚠️ **Tag values on writes are tag names/titles, not `tag_id` composites.** The verified
`Note.set` capture shows `tag=["TAGADDED"]` — a plain word, not a `Name@uid` string. Reads
(`Tag.list`'s `tag_id`) and writes (`Note.set`'s `tag` array) use different representations
of the same concept; the server resolves/creates by name on write.

### SYNO.NoteStation.FTS — v1 — V (full-text search)

```
api=SYNO.NoteStation.FTS&version=1&method=search
&keyword="<query>"&offset=0&limit=50
```
Returns `data.notes[]` in the same shape as `Note.list`. Not notebook-scoped — the client
narrows to the currently-browsed notebook itself if needed.

### SYNO.NoteStation.Shortcut — v1 — V

**`list`** → `data.shortcuts[]`, `data.total` — sidebar pinned/shortcut items (schema
below). Read-only in this project so far; create/delete not implemented.

### SYNO.Core.UserSettings — v1 — V

**`apply`** — persists UI preferences server-side as a double-JSON-encoded blob:
```
data="{\"SYNO.SDS.NoteStation.Application\":{
  \"view_by\":\"snippet\",
  \"sort_info\":{\"sort_by\":...,\"sort_direction\":...},
  \"todo_filter_date\"/\"priority\"/\"status\":...,
  \"notebook_full_menu_states\":{...},
  \"snippetview_width\":...,\"restoreSizePos\":...}}"
```
This is where card/snippet view choice, sort order, and todo filters persist across
sessions in the stock client. Not implemented — this project keeps such prefs local
(`shared_preferences`) instead of round-tripping to DSM.

---

## Client-side note encryption scheme — V

Fully reversed from `captures/Note.Encrypt.Decrypt.txt` (decrypt direction) and confirmed
symmetric by the encrypt-write capture above. **There is no server-side decrypt API** — the
server only ever stores/returns ciphertext; all encryption and decryption happens in the
client. Implemented in `lib/core/crypto/note_crypto.dart`, with round-trip tests in
`test/note_crypto_test.dart`.

- **Envelope**: OpenSSL/CryptoJS `"Salted__"` (8 bytes) + salt (8 bytes) + ciphertext,
  base64-encoded as the note's `content` field. Base64 prefix `U2FsdGVkX1` reliably
  identifies an encrypted blob without decoding it.
- **Cipher**: AES-256-CBC, PKCS#7 padding.
- **KDF**: OpenSSL `EVP_BytesToKey`, MD5, 1 iteration, over `(password + salt)` → first 32
  bytes = key, next 16 bytes = IV. Matches `openssl enc -aes-256-cbc -md md5`.
- **Plaintext shape**: the decrypted bytes are `"NoTeStAtIoNMaGic"` (16-char marker) +
  the note's real HTML. The marker is how the client verifies the password was correct
  without any separate verification field — wrong password ⇒ PKCS#7 unpad fails, or (in the
  rare case padding happens to validate) the marker is absent. Either way ⇒ reject as wrong
  password.
- **Salt**: a fresh random 8 bytes every time a note is (re-)encrypted — verified in this
  project's own encrypt implementation (never reuses key/IV across calls); the stock
  client's behavior here wasn't independently re-derived but OpenSSL's own tooling always
  behaves this way.

⚠️ Attachments use a **different, still-undecoded** envelope — `"Saltv2__"` (not
`"Salted__"`), see the .nsx section below. Do not assume the note-text scheme applies to
attachment bytes.

---

## Verified object schemas

All fields below are verified from `captures/Sync.Entry.Request.txt` (real server
responses). Canonical field names — the Dart models must match these, not guesses.

### Note (`Note.list` v3 → `data.notes[]`; `Note.get` v3 → `data` directly)
```
object_id   string   the note id, e.g. "1026_QF644RE9V50IT7EO6BU21NUFRG"   ← not note_id
parent_id   string   owning notebook's object_id (or "1026_#00000000" if none)
title       string
brief       string   plain-text snippet/preview   ← not "snippet"; PLAINTEXT even when encrypted
content     string   HTML, or a "U2FsdGVkX1..." blob when encrypt=true — Note.get/set only,
                     NOT present in Note.list responses
tag         string[] tag NAMES — Note.get only, NOT present in Note.list responses (see Tag)
ctime/mtime int      epoch SECONDS
encrypt     bool     is-encrypted   ← not "is_encrypted"
recycle     bool     in trash
archive     bool
category    string   "note"
perm        string   "owner" | ...
owner       {display_name, uid}
acl         {} | {enabled, public:{inherit, perm:"ro"}}
commit_msg  {} | {device, listable}   (last-edit metadata; only if requested via field={commit_msg:true})
link_id     string   short public-link id (only if requested via field={link_id:true})
ver         string   content revision hash (sha1) — required for `set`'s optimistic concurrency
thumb       null | {ext,height,width,md5,name,rotate,size,thumb_source,type:"image"}
attachment  null | {<ref_id>: {md5,name,ext,type,size,width,height,rotate,ref,source}}
```

### Notebook (`Notebook.list` v2 → `data.notebooks[]`, `data.total`)
```
object_id   string   the notebook id   ← not notebook_id
title       string
stack       string   owning shelf/stack title ("" = none)   ← not stack_id
items       string[] ordered note object_ids → note count = items.length   ← not note_count
ctime/mtime int      epoch seconds
archive     bool     ← not "archived"
individual_shared bool   ← not "shared"
preset      bool     built-in notebook (e.g. the default "Notes" notebook)
link_id, ver, perm, owner, acl, category:"notebook"
```

### Tag (`Tag.list` v1 → `data.tags[]`, `data.total`)
```
tag_id   string   "Name@uid", e.g. "Accounts@1026"   ← composite, NOT a ULID, NOT what
                                                        Note.set's `tag` array expects (that
                                                        takes plain names — see above)
title    string   ← the plain name; this is what Note.set's `tag` array uses
items    string[] note object_ids carrying this tag — the ONLY way to learn a note's tags
                  in bulk, since Note.list omits `tag` entirely
category "tag"
```

### Shortcut (`Shortcut.list` v1 → `data.shortcuts[]`, `data.total`)
```
id       string   target object_id
category string   "note" (also plausibly "notebook" — not confirmed)
title    string
items    null
owner, acl
```

### Todo (`Todo.list` v1 → `data`) — partial, envelope only
```
{count:0, offset:0, total:0}   ← captured while empty; item shape unknown.
```
See "Inferred APIs" below for the guessed item shape pending a real capture.

### Smart (`Smart.list` v1 → `data`) — partial, envelope only
```
{offset:0, total:0}   ← captured while empty; criteria/shape unknown.
```

### Cross-cutting
- IDs are `<volumeId>_<ULID>`; the per-object key is **`object_id`** everywhere in API
  responses (list and write). Only inside a `.nsx` export does the id move to the filename.
- `ver` (sha1) is the natural content-revision handle for both conflict detection and any
  future incremental-sync design.
- Timestamps are epoch **seconds** (×1000 for Dart `DateTime`).

---

## Inferred / not-yet-verified APIs

Everything in this section is a **guess** derived from the verified patterns above. Marked
🔲/📝 in the status table. Do not ship destructive or hard-to-reverse behavior against any
of these without a real capture first.

### SYNO.NoteStation.Note.Polling + Notebook.Polling — v1-3 / v1 — the most valuable capture left

Architecturally the most important gap: this is presumably how the stock client does
incremental sync (local mirror + "what changed since token X") rather than re-listing
everything, and would inform any future offline-sync design (`local_notes_repository.dart`).

Mental model to confirm:
1. Initial full sync via the already-verified `Notebook.list` + `Note.list`.
2. Server hands back a sync token/revision (guess: `pack`, `sync_token`, or per-object
   `ver`).
3. Client polls with the last token → server returns only changed/deleted objects + a new
   token.
4. Unknown: method name (`request`/`poll`/`list`/`get`), token param name and where it lives
   in the response, whether a changed note returns full content or just id+mtime (bandwidth
   design depends on this), whether deletes surface here or only via trash, and whether
   there's a long-poll/`timeout` blocking mode vs. pure client-interval polling.

Capture recipe: leave the web UI open and idle with DevTools recording to catch the
*automatic* background poll (reveals the method + token param with zero guessing), then
edit a note in a second tab and capture the next poll to see how a change is represented.

### SYNO.NoteStation.Todo — v1-2 — guessed shape, needs capture

Powers the to-do list: tasks classified starred/overdue/due-within-7-days, with priority,
scheduling, DSM-notification reminders, and subtasks (a note holds up to 50 tasks per
`requirements.txt`). Open question the `list` capture would answer: are todos first-class
objects with their own ids, or always children of a note?

```
list    — version=2, maybe notebook_id / filter=all|starred|overdue|due7
create  — title, note_id?, due_date?, priority?, parent_id? (for subtask)
update  — todo_id, + any of title/done|is_done/priority/due_date/reminder/is_starred
delete  — todo_id
```
Unknowns: object key name (`todo_id` vs `object_id`), done-flag name, date format (other
Note APIs use epoch seconds — likely the same), subtask linkage, reminder representation.

### SYNO.NoteStation.Smart — v1 — needs capture

Smart (saved-search) notebooks. Capturing a create with a couple of criteria is high value
— it's the best available window into how the wire format encodes nested/array params for
APIs beyond the simple ones already verified.

### Everything else (P2-P4, no capture yet)

`Note.Version` (restore an old revision), `SYNO.API.Encryption` (RSA-wrapped passwords, if
the stock client uses one — not observed in any capture so far, ours sends plaintext
passwords over HTTPS same as the verified Note.Encrypt capture), `Share.Priv`/`Shard`/
`Shard.Link` (sharing + public links), `Permission`/`Permission.User`/`.Group`/`.Public`,
`Export.Note`/`Export.Notebook`/`Export.Word`, `Import.Notebook`/`Import.Enex`/
`Import.Evernote`, `Notebook.Preset` (templates), `Setting`/`Setting.Global`, `Info`. No
capture attempted yet for any of these — treat every param/response shape as unknown until
one exists.

---

## .nsx export file format — V

Reverse-engineered from a real DSM Note Station export (one notebook with one encrypted
note + attachments, 2026-06-21). Implemented in `lib/core/nsx/nsx_codec.dart`.

**Container**: a plain **ZIP**. Entries are not in subfolders; each object is a top-level
entry **named by its `object_id`** (the id is the filename, not a JSON field inside it —
the opposite of every API response). Plus a `config.json` manifest and `file_*` attachment
blobs.

```
config.json                              manifest
<notebook object_id>                     notebook JSON
<note object_id>                         note JSON
file[_enc]_<note object_id>_<md5>        attachment bytes
```

**config.json**
```json
{ "note": ["<note object_id>", ...], "notebook": ["<notebook object_id>", ...],
  "shortcut": {"id": [], "stack": [], "tag": []}, "todo": [] }
```

**Notebook entry**
```json
{ "category": "notebook", "ctime": 1782074349, "mtime": 1782074349,
  "stack": "", "title": "TEST" }
```

**Note entry** — maps cleanly onto the live-API field names above (`brief`→excerpt,
`tag`→tags, `encrypt`→isEncrypted, `ctime`/`mtime`→created/updatedAt):
```json
{ "parent_id": "<notebook object_id>", "title": "...",
  "content": "<HTML, or a 'U2FsdGVkX1...' blob when encrypt=true>",
  "brief": "plain-text preview", "tag": ["TAGADDED"], "encrypt": true,
  "ctime": 1782082631, "mtime": 1782082631,
  "latitude": 0, "longitude": 0, "location": "", "source_url": "",
  "attachment": { "<ref_id>": { "md5": "...", "name": "...", "ext": "png",
    "type": "image", "size": 698004, "width": 1024, "height": 1024,
    "rotate": true, "ref": "<base64>", "source": "..." } } }
```

**Attachments**: entry name `file_<noteid>_<md5>` (plain) or `file_enc_<noteid>_<md5>`
(encrypted note); `<md5>` matches an `attachment[*].md5` in the note JSON.

⚠️ Encrypted attachment blobs start with **`Saltv2__`** — a *different* envelope than the
note-text `Salted__` scheme documented above. Its KDF/cipher is **not yet decoded**; the
codec carries these bytes opaquely (preserved byte-for-byte on decode→encode round-trip,
never decrypted or rendered).

---

## Open questions / what's still needed

In priority order (see `CAPTURE-CHECKLIST.md` for the exact click-by-click steps):

1. **Note.Polling / Notebook.Polling** — the incremental-sync backbone; highest value, do
   first.
2. **Rich-text HTML schema** — DONE. The rich WebView editor described here as "planned" has
   since been built; its confirmed-preserved tag/attribute/style vocabulary lives in
   `lib/core/rich_html/rich_html_schema.dart`, not in this file.
3. **Todo** — list/create/update(star/due/priority)/subtask/done/delete.
4. **Smart** — create with criteria (reveals nested-param wire encoding for everything
   else still unstarted).
5. ~~Attachments~~ — DONE (2026-07-25 capture): upload is `Note.set` multipart, download is
   the ticket-gated `ns/dv/` path — see the Core NoteStation APIs section above, not a
   separate `FileStation.Upload` call as originally guessed here.
6. **Restore from trash** and **permanent purge** — the two missing pieces of the
   trash/recycle-bin story (see the Note.delete section above).
7. **Change password / remove encryption** on an already-encrypted note.
8. P2+: version history, sharing, public links, permissions, export/import formats,
   notebook templates, settings.

## Source captures index

Raw, unedited evidence lives in `captures/`:

- `Note.CRUD.txt` — login, create/format/encrypt-flow note, full CRUD conventions
- `Note.Encrypt.txt` — `Note.Encrypt create` request/response
- `Note.Encrypt.Decrypt.txt` — client-side decryption, fully reversed
- `Note.Encrypt.write.txt` — encrypting a note end to end (`Note.copy` + `Note.Encrypt.create`)
- `Note.Ghost.txt` — moving a note to trash (`Note.delete recycle=true`)
- `Sync.Entry.Request.txt` — startup batch sync, standalone Note.list, attachment download,
  UI-prefs persistence; source of the verified object schemas above
- `NSX-format.md` — the .nsx export container format
- `checkbox.har`, `encrypt`, `trash.har` — raw HARs behind the above `.txt` summaries
