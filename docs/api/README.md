# NoteStation API Mapping

Working spec for every `SYNO.NoteStation.*` API needed to reach full parity with the
stock Note Station client. Source of truth for the Dart service layer
(`lib/core/services/note_station_service.dart`).

## How this folder works

- One `.md` file per API (e.g. `SYNO.NoteStation.Todo.md`).
- Each spec lists methods, params, and a **real captured request/response** where we have one.
- `query.cgi` gives us API names + version ranges only — **not** methods or params.
  Methods/params come from one of three sources, in order of trust:
  1. **Live capture** — stock NoteStation web UI + browser DevTools → Network tab → the
     `entry.cgi` POST body. This is ground truth. Save it under `captures/`.
  2. **Web UI JS** — grep the minified NoteStation bundle for the API string.
  3. **Inference** — derived from the Note/Notebook/Tag pattern. Marked clearly; must be
     verified before shipping.

## Conventions (verify against `Note.Encrypt` capture)

- Endpoint: `POST /webapi/entry.cgi`
- Common params on every call: `api`, `method`, `version`, `_sid`
- **Open question — param value encoding.** The one real capture we have
  (`captures/Note.Encrypt.txt`) shows JSON-quoted values:
  `object_id=%22..%22` → `object_id="..."`. But `note_station_service.dart` passes bare
  strings. ⚠️ Resolve this first — see `_CONVENTIONS.md`.
- IDs look like `1026_QF644RE9V50IT7EO6BU21NUFRG` (`<volume>_<ULID>`).
- Object-addressing param is sometimes `object_id` (Encrypt) and sometimes
  `note_id` / `notebook_id` (CRUD). Confirm per API.

## Status

Legend: ✅ implemented · 📝 spec mapped (needs capture to verify) · 🔲 not started
Confidence: **V** = verified by live capture · **I** = inferred

| Priority | API | Versions | Status | Conf | Feature |
|---|---|---|---|---|---|
| done | SYNO.NoteStation.Stack | 1 | ✅ | V | Shelves |
| done | SYNO.NoteStation.Notebook | 1-2 | ✅ | V | Notebooks |
| done | SYNO.NoteStation.Note | 1-4 | ✅ | V | Notes CRUD |
| done | SYNO.NoteStation.Tag | 1-2 | ✅ | V | Tags |
| done | SYNO.NoteStation.FTS | 1 | ✅ | V | Search |
| P1 | SYNO.Entry.Request | 1-2 | ✅ | **V** | Batch calls (startup sync) |
| P1 | SYNO.NoteStation.Todo | 1-2 | 📝 | V* | Tasks/todos (envelope only; empty) |
| P1 | SYNO.NoteStation.Note.Polling | 1-3 | 📝 | I | Note sync (incremental) |
| P1 | SYNO.NoteStation.Notebook.Polling | 1 | 📝 | I | Notebook sync |
| P1 | SYNO.NoteStation.Smart | 1 | 📝 | V* | Smart notebooks (envelope only; empty) |
| P1 | SYNO.NoteStation.Shortcut | 1 | ✅ | **V** | Sidebar shortcuts |
| P1 | SYNO.NoteStation.Note (download) | 3 | ✅ | **V** | Attachment/thumb GET |
| P1 | SYNO.Core.UserSettings | 1 | ✅ | **V** | View/sort/todo-filter prefs |
| P1 | SYNO.FileStation.Upload | 2-3 | 🔲 | I | Attachment upload |
| P2 | SYNO.NoteStation.Note.Version | 1-2 | 🔲 | I | Version history |
| P2 | SYNO.NoteStation.Note.Encrypt | 1 | 🔲 | **V** | Note encryption |
| P2 | SYNO.API.Encryption | 1 | 🔲 | I | RSA for passwords |
| P2 | SYNO.NoteStation.Share.Priv | 1-2 | 🔲 | I | Sharing |
| P2 | SYNO.NoteStation.Shard | 1 | 🔲 | I | Public share links |
| P2 | SYNO.NoteStation.Shard.Link | 1 | 🔲 | I | Share link mgmt |
| P2 | SYNO.NoteStation.Permission | 1 | 🔲 | I | Perms (root) |
| P2 | SYNO.NoteStation.Permission.User | 1 | 🔲 | I | Per-user perms |
| P2 | SYNO.NoteStation.Permission.Group | 1 | 🔲 | I | Per-group perms |
| P2 | SYNO.NoteStation.Permission.Public | 1 | 🔲 | I | Public perms |
| P3 | SYNO.NoteStation.Export.Note | 1 | 🔲 | I | Export note |
| P3 | SYNO.NoteStation.Export.Notebook | 1 | 🔲 | I | Export .nsx |
| P3 | SYNO.NoteStation.Export.Word | 1 | 🔲 | I | Export .docx |
| P3 | SYNO.NoteStation.Import.Notebook | 1 | 🔲 | I | Import .nsx |
| P3 | SYNO.NoteStation.Import.Enex | 1 | 🔲 | I | Import .enex |
| P3 | SYNO.NoteStation.Import.Evernote | 1 | 🔲 | I | Import Evernote |
| P4 | SYNO.NoteStation.Shortcut | 1 | 🔲 | I | Sidebar shortcuts |
| P4 | SYNO.NoteStation.Notebook.Preset | 1 | 🔲 | I | Notebook templates |
| P4 | SYNO.NoteStation.Note.Ghost | 2-3 | 🔲 | I | Trash / recovery |
| P4 | SYNO.NoteStation.Setting | 1-2 | 🔲 | I | User settings |
| P4 | SYNO.NoteStation.Setting.Global | 1 | 🔲 | I | Global settings |
| P4 | SYNO.NoteStation.Info | 1-3 | 🔲 | I | Service info |

See `CAPTURE-CHECKLIST.md` for exactly what to click in the web UI to fill each gap.
