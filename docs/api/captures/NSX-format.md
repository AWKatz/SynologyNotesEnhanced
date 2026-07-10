# .nsx export format (VERIFIED 2026-06-21)

Reverse-engineered from a real DSM Note Station export
(`20260621_185732_17815_Aaron.nsx`, one notebook "TEST" with one encrypted note + attachments).

## Container
A plain **ZIP** archive (extension `.nsx`). Entries are **not** in subfolders; each
object is a top-level entry **named by its `object_id`** (no extension). Plus a
`config.json` manifest and `file_*` attachment blobs.

```
config.json                              manifest
<notebook object_id>                     notebook JSON   e.g. 1026_KDLIK0SVJH7RJ4TA3NIFLV49P0
<note object_id>                         note JSON       e.g. 1026_V9LA3B1CE54HL8BFVNR2P839U4
file[_enc]_<note object_id>_<md5>        attachment bytes (see Attachments)
```

The object's id is the **filename**, NOT a field inside the JSON.

## config.json
```json
{
  "note":     ["<note object_id>", ...],
  "notebook": ["<notebook object_id>", ...],
  "shortcut": { "id": ["<object_id>", ...], "stack": [], "tag": [] },
  "todo":     []
}
```

## Notebook JSON
```json
{ "category": "notebook", "ctime": 1782074349, "mtime": 1782074349,
  "stack": "",            // shelf title, "" = none
  "title": "TEST" }
```

## Note JSON
```json
{ "parent_id": "<notebook object_id>",
  "title": "...",
  "content": "<HTML, OR 'U2FsdGVkX1...' encrypted blob when encrypt=true>",
  "brief": "plain-text preview",
  "tag": ["TAGADDED"],
  "encrypt": true,
  "ctime": 1782082631, "mtime": 1782082631,
  "latitude": 0, "longitude": 0, "location": "", "source_url": "",
  "attachment": {
    "<ref_id>": {                          // e.g. "_ATPjgj18ccmsOI9va1rcvg"
      "md5": "a535d8920ecafeb121cdae6fedd9b17a",  // links to file_* entry
      "name": "AppIcon.png", "ext": "png", "type": "image",
      "size": 698004, "width": 1024, "height": 1024,
      "rotate": true, "ref": "<base64>", "source": "..."
    }
  }
}
```
Maps cleanly to our models: id=filename, parent_id→notebookId, brief→excerpt,
tag→tags, encrypt→isEncrypted, ctime/mtime→created/updatedAt. (Same field names the
live API uses — see NoteStation-schemas.md / Note.CRUD.txt.)

## Attachments
Entry name: `file_<noteid>_<md5>` (plain) or `file_enc_<noteid>_<md5>` (encrypted note).
`<md5>` matches an `attachment[*].md5` in the note JSON. (A `_thumb`-like extra md5 not
present in the metadata may also appear.)

⚠ Encrypted attachment blobs start with **`Saltv2__`** (8-byte header) — a DIFFERENT
envelope than the note **text** content's `Salted__` (which we decrypt in NoteCrypto).
The `Saltv2__` KDF/cipher is NOT yet decoded; our codec carries attachment bytes
**opaquely** (preserved on round-trip, not decrypted/rendered).
