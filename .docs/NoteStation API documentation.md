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
| SYNO.NoteStation.Info | 2 | ✅ | V | ✅ | Account info (uid/username/is_admin) — needed to build Smart-notebook tag criteria |
| SYNO.NoteStation.Todo | 1-2 | ✅ | V | ✅ | Tasks + subtasks: list/create/set/delete, `parent_id` for subtasks |
| SYNO.NoteStation.Smart | 1 | ✅ | V | ✅ | Smart notebooks: create/list; "opening" one is `Note.list` with `perm_from`/`smart_id` |
| SYNO.NoteStation.Note.Version | 2 | ✅ | V | ✅ | Version history: list/restore; `Note.get` gained a `ver` param |
| SYNO.NoteStation.Share.Priv | 2 | ✅ | V | ✅ | User/group autocomplete search for sharing |
| SYNO.NoteStation.Shard.Link | 1 | ✅ | V | ✅ | Public share link (get only) |
| SYNO.NoteStation.Permission | 1 | ✅ | V | ✅ | Note-level sharing on/off |
| SYNO.NoteStation.Permission.Public | 1 | ✅ | V | ✅ | Public link perm set/delete |
| SYNO.NoteStation.Permission.Group | 1 | ✅ | V/I | ✅ | `set` verified; `delete` is an unverified guess (see below) |
| SYNO.NoteStation.Permission.User | 1 | ✅ | V | ✅ | Individual-user share set/delete, incl. `perm:"rw"` |
| SYNO.NoteStation.Export.Notebook | 1 | ✅ | V | ✅ | Server-side async .nsx export job (start/status) — distinct from this project's own local `.nsx` codec |
| SYNO.NoteStation.Import.Notebook | 1 | ✅ | V | ✅ | Server-side async .nsx import job (start/status), reading a file already on the NAS |
| SYNO.NoteStation.Note.Polling | 1-3 | 📝 | I | — | Incremental sync — not captured |
| SYNO.NoteStation.Notebook.Polling | 1 | 📝 | I | — | Incremental sync — not captured |
| SYNO.API.Encryption | 1 | 🔲 | I | — | RSA-wrapped passwords (if used) |
| SYNO.NoteStation.Export.Note / Export.Word | 1 | 🔲 | I | — | Single-note export formats |
| SYNO.NoteStation.Import.Enex / Import.Evernote | 1 | 🔲 | I | — | Import from Evernote |
| SYNO.NoteStation.Notebook.Preset | 1 | 🔲 | I | — | Notebook templates |
| SYNO.NoteStation.Setting / Setting.Global | 1-2 | 🔲 | I | — | User/global settings |

Restore-from-trash and permanent purge are **not** a separate `Ghost` API — both are on
`SYNO.NoteStation.Note` itself: `restore` (dedicated method) and `delete` with
`recycle=false` applied to an already-trashed note (purge). See below.

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

**`delete`** (move to trash) — v3 — V, confirmed 2026-07-19 and again in
`Recyling Bin Delete and Restore*.har`:
```
api=SYNO.NoteStation.Note&version=3&method=delete
&object_id=["<id>"]&recycle=true
```
`object_id` is a **JSON array** even for a single note (batch-capable). This is a **soft**
delete — it flips the note's `recycle` flag; the object isn't removed. A subsequent `list`
with `filter:{"recycle":false,...}` no longer returns it.

**`delete` on an already-trashed note** (permanent purge) — v3 — V:
```
api=SYNO.NoteStation.Note&version=3&method=delete
&object_id=["<id>"]&recycle=false
```
Same endpoint/method as the soft-delete above — the meaning of `recycle` flips based on the
note's *current* state: applied to a live note it trashes; applied to an already-trashed
note it purges permanently. Only captured against an already-trashed note; calling this on a
live note has not been tested (would presumably just be a no-op restore-to-live-and-back, or
possibly nothing — untested).

**`restore`** (un-trash) — v3 — V, its own dedicated method (not `set`, and not the same
`restore` as `Note.Version` — see that section below):
```
api=SYNO.NoteStation.Note&version=3&method=restore&object_id=["<id>"]
```
`object_id` is a JSON array. The server restores the note to its original notebook on its
own — the note object carries an `old_parent_id` field while trashed (see schema below), but
this call doesn't need to pass it explicitly.

**`list` scoped to trash** — v3 — V: same endpoint as the main list above, with
`filter.recycle:true` instead of `false`. The capture's filter also explicitly included
`owner` (`{"recycle":true,"owner":<uid>,"archive":false}`) — the main `list` above works
fine without `owner`, so this may just be incidental to how the stock client happened to
build this particular call rather than a hard requirement.

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

### SYNO.NoteStation.Note.Version — v2 — V (version history)

**`list`** — versions of a note, newest-first-by-*lowest-id* (see note below):
```
api=SYNO.NoteStation.Note.Version&version=2&method=list
&object_id="<note id>"&limit=100&filter={"listable":true}
```
```json
{"data":{"count":3,"offset":0,"total":3,"versions":[
  {"id":1,"author":"Aaron","mtime":1785526837,
   "version":"8ca31fe286acc23e77dd17e8a0a709dec984af05",
   "commit_msg":{"device":"desktop","listable":true},
   "last_version":["33a458c20d9adf46bf8136b2e21e2623dc58ab07"]},
  ...
]},"success":true}
```
⚠️ **The lowest `id` is the CURRENT content, and `id` increases going further back in
time** — the reverse of what "id" might suggest. Confirmed by cross-referencing: `id:1`'s
`version`/`mtime` exactly matched a `Note.get` taken moments earlier in the same capture.
`version` (despite the name collision) is the same value both `Note.get`'s `ver` param and
`Note.Version.restore`'s `ver` param key on — NOT the field literally named `ver` elsewhere;
here it's nested under `versions[].version`.

**`Note.get` with a `ver` param** — fetches a specific historical revision's content instead
of the current one:
```
api=SYNO.NoteStation.Note&version=3&method=get
&object_id="<id>"&ver="<a versions[].version value from Note.Version.list>"
```
Otherwise identical to the normal `get` documented above.

**`restore`** — restores the note to a given revision, **in place** (a real mutation, not a
preview):
```
api=SYNO.NoteStation.Note.Version&version=2&method=restore
&object_id="<id>"&ver="<versions[].version value>"
```
Response comes back with `commit_msg:{"action":"restore"}` and a fresh `ver`/`mtime`, same
shape as a normal `Note.get`. This is a **different `restore`** than `SYNO.NoteStation.Note`
`restore` (un-trash, see above) — same verb, different API, different purpose.

### SYNO.NoteStation.Todo — v1(list, in the startup batch)/v2(list/create/set)/v1(delete) — V

Tasks are first-class objects with their own `object_id`, not embedded in a note (unless
explicitly linked via `note_id`). Subtasks are just Todos with a `parent_id`.

**`list`**
```
api=SYNO.NoteStation.Todo&version=2&method=list
&field={"items":true}&filter={}&offset=0&limit=100
&sort_by="due_date"&sort_direction="asc"
```
`field.items:true` requests subtasks. `filter` can scope: `{"parent_id":"<id>"}` for one
task's subtasks, or `{"note_id":["<note object_id>"]}` for todos linked to a note.
```json
{"data":{"count":1,"offset":0,"todos":[
  {"object_id":"1026_...","title":"NEW TASK","comment":"","done":false,"star":false,
   "priority":-1,"due_date":-1,"parent_id":"","note_id":"","note_parent_id":"",
   "note_title":"","reminder_offset":-1,
   "items":["1026_subtaskA","1026_subtaskB"]}
]},"success":true}
```
⚠️ **A parent's `items` field is an array of subtask `object_id` STRINGS, not nested todo
objects.** Fetch a subtask's own fields with a separate `list` call filtered by
`parent_id`. `priority:-1`/`due_date:-1` mean "not set".

**`create`**
```
api=SYNO.NoteStation.Todo&version=2&method=create
&title="Task title"
&due_date=1788210000        (optional — epoch SECONDS; only ever captured at create time)
&parent_id="<parent task's object_id>"   (optional — creates a SUBTASK)
```
Response is the new todo directly under `data` (same "create returns the object directly"
pattern as `Note.create`).

**`set`** (update) — each field captured as its own independent call, but presumably
combinable:
```
api=SYNO.NoteStation.Todo&version=2&method=set
&object_id=["<id>"]
&comment="free text"    | &priority=300    | &star=true    | &done=true
```
`object_id` is a JSON array (batch-capable), same convention as `Note.delete`. `priority`'s
bucket boundaries are **not verified** — only `300` has ever been captured; treat any other
value as an inference. `title`/`due_date` as a later edit (vs. only at create) are also
unverified but very likely accepted here by symmetry with every other field being a plain
optional param on the same generic object-update call.

**`delete`** — ⚠️ **v1, NOT v2** (list/create/set are v2 — easy to get wrong):
```
api=SYNO.NoteStation.Todo&version=1&method=delete&object_id=["<id>"]
```

### SYNO.NoteStation.Smart — v1 — V (smart/saved-search notebooks)

**`create`** — the "critical" capture per the old checklist, since it reveals nested/array
param encoding:
```
api=SYNO.NoteStation.Smart&version=1&method=create
&title="Smart Notebook"
&query={"keyword":"SMART","title":"THIS IS A SMART NOTEBOOK",
        "tag":["Mom's Recipies@1026"],"tag_operator":"and",
        "parent_id":["1026_<notebook id>"]}
&commit_msg={"device":"desktop"}
```
```json
{"data":{"link_id":"hGOJo","object_id":"1026_..."},"success":true}
```
⚠️ **`query.tag` is an array of `"<tagName>@<uid>"` strings — the tag's NAME, not its
`tag_id`.** All four `query` keys are optional/independent; `keyword` searches note content,
`title` restricts by note title, `tag`/`tag_operator` (`"and"`/`"or"`) restrict by tag
membership, `parent_id` (an array) restricts to specific notebooks.

**`list`** → `data.smarts[]`, `data.total`. Only title/metadata — **does NOT echo the
`query` back**, and no `Smart.get` (or equivalent) has ever been observed, so an existing
smart notebook's criteria can't be recovered from the server at all once you don't already
know it client-side.

**"Opening" a smart notebook** (i.e. fetching its matching notes) is **not a separate
endpoint** — it's the same `Note.list` v3 call used everywhere, with two extra top-level
params instead of `filter.parent_id`:
```
api=SYNO.NoteStation.Note&version=3&method=list
&filter={"recycle":false,"owner":<uid>}&field={}
&offset=0&limit=50&sort_by="title"&sort_direction="desc"
&perm_from="smart"&smart_id="<the smart notebook's object_id>"
```
The server computes the match itself. Note this `filter`/`field` shape differs subtly from
the normal `Note.list` (no `archive` key in filter; `field` is empty instead of requesting
`link_id`/`commit_msg`) — unexplained, but worth mirroring exactly rather than assuming it's
interchangeable with the main note list call.

### SYNO.NoteStation.Share.Priv / Shard.Link / Permission* — V (sharing)

**`Share.Priv` `list`** — v2 — autocomplete search over DSM users/groups:
```
api=SYNO.NoteStation.Share.Priv&version=2&method=list&query="ad"
```
```json
{"data":{"list":[{"name":"admin","type":"user"},{"name":"administrators","type":"group"}],
 "offset":0,"total":2},"success":true}
```

**`Shard.Link` `get`** — v1 — the note's public share URL:
```
api=SYNO.NoteStation.Shard.Link&version=1&method=get
&object_id="<note id>"&mode="public"
```
```json
{"data":{"mode":"ddns","url":"https://<host>:5001/ns/sharing/<link_id>"},"success":true}
```
`mode="private"` is plausible (public is the only value ever captured) but unconfirmed.

**`Permission` `set`** — v1 — turns note-level sharing on as a whole. Always seen paired
with a `Permission.Public`/`.Group`/`.User` `set` in the same UI action (captured as two
separate sequential `entry.cgi` calls, or batched via `SYNO.Entry.Request` — functionally
the same either way):
```
api=SYNO.NoteStation.Permission&version=1&method=set
&object_id="<note id>"&enabled=true
```
`enabled:false` has **never** been captured — not even the public-link *revoke* flow touches
it (see below). Treat "disable sharing entirely" as unverified.

**`Permission.Public` `set`/`delete`** — v1 — the public link's own permission:
```
api=SYNO.NoteStation.Permission.Public&version=1&method=set
&object_id="<note id>"&perm="ro"

api=SYNO.NoteStation.Permission.Public&version=1&method=delete
&object_id="<note id>"
```
`delete` (object_id only) fully revokes the public link — this is the one confirmed "remove
a share" call. `perm` is only ever confirmed as `"ro"` on THIS specific endpoint (see
`Permission.User` below for where `"rw"` was actually observed).

**`Permission.Group` `set`** — v1 — shares with a DSM group:
```
api=SYNO.NoteStation.Permission.Group&version=1&method=set
&object_id="<note id>"&groupname="administrators"&perm="ro"
```
No `Permission.Group` `delete` has been captured — this project ships one anyway, **as an
explicit, labeled guess** (`groupname` + a `gid` int mirroring `Permission.User`'s own
`uid` — see immediately below), because removing it was requested without a fresh capture.
If it misbehaves in the real app, that guessed shape is the first thing to re-capture.

**`Permission.User` `set`/`delete`** — v1 — shares with an individual DSM user:
```
api=SYNO.NoteStation.Permission.User&version=1&method=set
&object_id="<note id>"&username="admin"&perm="rw"

api=SYNO.NoteStation.Permission.User&version=1&method=delete
&object_id="<note id>"&username="admin"&uid=1024
```
⚠️ **`perm:"rw"` is confirmed here** (the only endpoint where a non-`"ro"` value has ever
been captured). ⚠️ **`delete` needs BOTH `username` and `uid`, and `uid` rides as a BARE
JSON NUMBER** (`uid=1024`, not a quoted string) — even though the identical value appears as
a **string** map-key in `Note.acl.dsm_user` (see schema below). Easy to regress if this is
touched without re-checking.

**Resulting `Note.acl` shape** (returned by `Note.get`/`Note.list` once shared):
```json
{"enabled":true,
 "public":{"inherit":false,"perm":"ro"},
 "dsm_group":{"101":{"inherit":false,"name":"administrators","perm":"ro"}},
 "dsm_user":{"1024":{"inherit":false,"name":"admin","perm":"rw"}}}
```
The `dsm_group`/`dsm_user` map keys (`"101"`, `"1024"`) are the group/user's numeric id as a
**string** — this is where `Permission.User.delete`'s `uid` value comes from (parsed back to
an int for that call).

### SYNO.NoteStation.Export.Notebook / Import.Notebook — v1 — V (server-side .nsx job)

Distinct from this project's own **local** `.nsx` codec (`lib/core/nsx/nsx_codec.dart` —
parses/builds the ZIP format directly, client-side, no server API involved at all). This is
the real NAS's own **async job**, which writes/reads the `.nsx` file to/from a folder **on
the NAS itself** — moving that file to/from the client device still needs a separate
FileStation upload/download, which has no capture yet (no FileStation folder-browse capture
exists), so this project's UI takes a plain NAS path string instead of a real picker.

**`Export.Notebook` `start`**:
```
api=SYNO.NoteStation.Export.Notebook&version=1&method=start
&object_id=null&save_config=false&dest="/Downloads"&export_todo=true
```
```json
{"data":{"task_id":"Aaron/NoteStation_Export17855266788494DB49"},"success":true}
```
⚠️ **`object_id=null` (export every notebook) is sent as a LITERAL JSON `null`, not an
omitted param.** `dest` is a NAS-relative folder path.

**`Export.Notebook` `status`** — no params; poll until `finish:true`:
```json
{"data":{"auto_remove":false,"finish":true,
 "data":{"current":9,"total":9,"finish_time":1785526678},
 "info":{...}},"success":true}
```

**`Import.Notebook` `start`** — reads a `.nsx` already sitting in a NAS folder:
```
api=SYNO.NoteStation.Import.Notebook&version=1&method=start
&file=[{"name":"20260731_153758_11781_Aaron.nsx","format":"ds",
        "path":"/Downloads/20260731_153758_11781_Aaron.nsx"}]
```
`file` is an array (batch-capable, one entry captured). `format:"ds"` was the only value
seen — meaning unconfirmed. `Import.Notebook status` mirrors `Export.Notebook status`'s
shape exactly.

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
acl         {} | {enabled, public:{inherit,perm}, dsm_group:{<gid>:{inherit,name,perm}},
                   dsm_user:{<uid>:{inherit,name,perm}}}   — see Sharing section for how
                                                              these three sub-keys populate
commit_msg  {} | {device, listable}   (last-edit metadata; only if requested via field={commit_msg:true})
link_id     string   short public-link id (only if requested via field={link_id:true})
ver         string   content revision hash (sha1) — required for `set`'s optimistic concurrency;
                     also what Note.Version.list's `versions[].version` and Note.get's `ver` key on
old_parent_id string the notebook it was in before being trashed — only present while `recycle:true`
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

### NoteVersion (`Note.Version.list` v2 → `data.versions[]`, `data.total`)
```
id          int      LOWEST = current/newest; increases going further back in time (see
                      the Note.Version section above — reverse of what "id" suggests)
version     string   sha1 — feeds Note.get's `ver` param and Note.Version.restore's `ver` param
author      string   display name
mtime       int      epoch seconds
commit_msg  {device, listable} | {action:"restore"}   (present on a version created by a restore)
last_version string[] (sha1 of the version this one superseded — purpose not otherwise explored)
```

### Todo (`Todo.list` v2 → `data.todos[]`, `data.count`/`data.total`)
```
object_id       string    the task id   ← not todo_id
title           string
comment         string    free-text note on the task (not the same as a linked note's content)
done            bool
star            bool
priority        int       -1 = unset. Bucket boundaries NOT verified — only 300 has ever
                          been captured (this project's UI guesses None/Low/Medium/High as
                          -1/100/200/300, flagged unverified in the Dart source)
due_date        int       epoch SECONDS, -1 = unset. Only ever captured being set at CREATE
                          time, never as a later edit (though `set` presumably accepts it —
                          same generic multi-field update shape as every other field here)
parent_id       string    "" = top-level task; a task's object_id = this is a SUBTASK of it
note_id         string    "" = not linked to a note
note_parent_id, note_title   string, only populated when note_id is set (untested)
reminder_offset int       -1 = unset. Unit/representation not explored.
items           string[]  child subtask object_ids (see the Todo API section above — NOT
                          nested objects)
```

### Smart (`Smart.list` v1 → `data.smarts[]`, `data.total`)
```
object_id  string   the smart notebook id
title      string
category   "smart"
link_id, ctime, mtime, perm, owner, acl
```
⚠️ The `query` a smart notebook was created with (keyword/title/tag/tag_operator/parent_id —
see the Smart API section above) is **NOT** part of this list response and can't be
recovered from the server once you don't already know it — see that section for why
"opening" one doesn't need it anyway (server-side `perm_from`/`smart_id` scoping).

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

### Remaining unverified corners of otherwise-done APIs

These aren't whole unstarted APIs — see the Core NoteStation APIs section above for the
verified majority of each — just specific values/sub-flows within them that have no capture:

- **`Permission.Group` `delete`** (removing a single group's share) — this project ships a
  guessed shape anyway (see the Sharing section above); re-capture if it misbehaves.
- **`Permission` `set` with `enabled:false`** (disabling sharing entirely) — every capture,
  across five separate sharing-capture sessions, has only ever sent `enabled:true`.
- **`Permission.Public`/`.Group` `set` with `perm:"rw"`** — `"rw"` is confirmed on
  `Permission.User` only; inferred by symmetry for the other two (identical `{object_id,
  perm}`-shaped call).
- **Todo `set` with `title`/`due_date`** as a later edit (as opposed to only at `create`) —
  presumably works (same generic multi-field call as `comment`/`priority`/`star`/`done`,
  all independently verified there) but untested.
- **Todo `priority` bucket boundaries** — only the single value `300` has ever been
  captured.

### Everything else (P2-P4, no capture yet)

`SYNO.API.Encryption` (RSA-wrapped passwords, if the stock client uses one — not observed in
any capture so far, ours sends plaintext passwords over HTTPS same as the verified
Note.Encrypt capture), `Export.Note`/`Export.Word` (single-note export formats — distinct
from the now-verified `Export.Notebook`), `Import.Enex`/`Import.Evernote`, `Notebook.Preset`
(templates), `Setting`/`Setting.Global`, FileStation folder-browsing (would let the NSX
server-job UI use a real file/folder picker instead of plain path text fields), and the
rich-text schema's code-blocks/blockquotes vocabulary (tracked in
`lib/core/rich_html/rich_html_schema.dart`, not here — needs its own "apply everything"
`Note.get` capture). No capture attempted yet for any of these — treat every param/response
shape as unknown until one exists.

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

In priority order:

1. **Note.Polling / Notebook.Polling** — the incremental-sync backbone; the single biggest
   remaining gap, and the only P1-tier item left undone.
2. **Rich-text HTML schema** — mostly done (see `lib/core/rich_html/rich_html_schema.dart`
   for the confirmed vocabulary, not this file); code blocks and blockquotes still need
   their own "apply everything" `Note.get` capture.
3. ~~Todo~~ / ~~Smart~~ / ~~Attachments~~ / ~~Version history~~ / ~~Sharing~~ /
   ~~Export.Notebook/Import.Notebook~~ / ~~Trash restore/purge~~ — DONE, see the Core
   NoteStation APIs section above for each. Small named gaps remain within a few of these
   (Permission.Group delete, `enabled:false`, `rw` on Public/Group, Todo priority buckets)
   — see "Remaining unverified corners of otherwise-done APIs" above.
4. **Change password / remove encryption** on an already-encrypted note — not captured.
5. FileStation folder-browsing (blocks a real picker for the NSX export/import UI),
   `SYNO.API.Encryption`, `Export.Note`/`Export.Word`, `Import.Enex`/`Import.Evernote`,
   `Notebook.Preset`, `Setting`/`Setting.Global` — none captured, all lower priority.

## Source captures index

Raw, unedited evidence lives in `.docs/reference/` and `.docs/api/captures/` (both
gitignored — see the visibility note at the top of this file):

- `Note.CRUD.txt` — login, create/format/encrypt-flow note, full CRUD conventions
- `Note.Encrypt.txt` — `Note.Encrypt create` request/response
- `Note.Encrypt.Decrypt.txt` — client-side decryption, fully reversed
- `Note.Encrypt.write.txt` — encrypting a note end to end (`Note.copy` + `Note.Encrypt.create`)
- `Note.Ghost.txt` — moving a note to trash (`Note.delete recycle=true`)
- `Sync.Entry.Request.txt` — startup batch sync, standalone Note.list, attachment download,
  UI-prefs persistence; source of the verified object schemas above
- `NSX-format.md` — the .nsx export container format
- `checkbox.har`, `encrypt`, `trash.har` — raw HARs behind the above `.txt` summaries
- `To Do list capture[...].har`, `To Do list capture delete [...].har`,
  `Substasks [...].har` — Todo list/create/set/delete + subtask create/list
- `Smart Notebook [...].har` — `Smart.create`/`.list`
- `Create and Open Smart Notebook [...].har` — same, plus the `perm_from`/`smart_id`
  `Note.list` scoping that "opening" a smart notebook actually uses
- `Version restore [...].har` — `Note.Version.list`/`.restore`, `Note.get` with `ver`
- `Note Sharing and Permissions [...].har` — public link create/revoke, DSM-group share
- `Share RW [...].har` — individual-user share + `perm:"rw"` (`Permission.User.set`)
- `Revoke Share [...].har` — `Permission.User.delete`
- `Export nsx and Import [...].har` — the server-side async `Export.Notebook`/
  `Import.Notebook` job
- `Recyling Bin Delete and Restore [...].har` — trash-scoped `Note.list`, purge
  (`Note.delete recycle=false` on an already-trashed note), `Note.restore`
