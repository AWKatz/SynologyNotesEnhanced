# SYNO.NoteStation.Note.Polling + SYNO.NoteStation.Notebook.Polling

Versions: Note.Polling 1–3 · Notebook.Polling 1 · Status: 📝 inferred, needs capture
Feature: incremental sync — the backbone of offline mode.

This is the **most architecturally important** API to map and the hardest to guess, so we
do it early. The web/desktop client keeps a local mirror and asks the server "what changed
since token/timestamp X?" rather than re-listing everything. Getting the token semantics
right determines the entire offline-storage design (`local_notes_repository.dart`).

## Mental model (to confirm)

1. Initial full sync: `Notebook list` + `Note list` (already implemented).
2. Server hands back a **sync token / revision** (often `pack` or `sync_token` or a
   per-object `version`/`rev`).
3. Client polls `Polling` with the last token → server returns only changed/deleted
   objects + a new token.
4. Long-poll vs short-poll: v3 may support held connections (`timeout` param) like
   `SYNO.Entry.Request.Polling`. Confirm.

## Note.Polling — methods (inferred)

### `request` (or `poll` / `list`)
Params (likely): `version`, `pack`/`sync_token` (last seen), maybe `timeout`.
Expected response (guess):
```
{ pack: "<new token>",
  objects: [ { object_id, type:"note", action:"create|update|delete",
               notebook_id, mtime, ... } ] }
```
Key unknowns: the method name, the token param name, and whether deletes come through
here or via `Note.Ghost`.

## Notebook.Polling — methods (inferred)
Same shape, scoped to notebooks (rename / move / delete / archive). v1 only.

## Unknowns to confirm in capture (high value)
1. **Method name** — `request`, `poll`, `list`, or `get`?
2. **Token param + field** — what you send back and where it lives in the response.
3. **Granularity** — does a changed note return full content or just an id+mtime you then
   re-`get`? (Bandwidth design depends on this.)
4. **Deletes** — surfaced here, or only via `Note.Ghost` (trash)?
5. **Long-poll** — is there a `timeout`/blocking mode, or pure client-interval polling?
6. Relationship to `SYNO.Entry.Request.Polling` (generic long-poll wrapper).

## Capture steps
See `CAPTURE-CHECKLIST.md` § Sync. Leave the web UI open and idle with DevTools recording
to catch the **background poll** the client fires on its own — that single request reveals
the method + token param without guesswork. Then edit a note in a second tab and capture
the next poll to see how a change is represented.
