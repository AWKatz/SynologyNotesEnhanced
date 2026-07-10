# Verified object schemas

All fields below are **verified** from `captures/Sync.Entry.Request.txt` (real server
responses, 2026-06-21). These are the canonical field names — our Dart models must match.

## Note (SYNO.NoteStation.Note `list` v3 → `data.notes[]`)
```
object_id   string   THE NOTE ID (e.g. "1026_QF644RE9V50IT7EO6BU21NUFRG")  ← not note_id
parent_id   string   owning notebook's object_id (or "1026_#00000000" if none)  ← not notebook_id
title       string
brief       string   plain-text snippet/preview  ← not "snippet"
ctime       int      epoch SECONDS
mtime       int      epoch SECONDS
encrypt     bool     is-encrypted  ← not "is_encrypted"
recycle     bool     in trash
archive     bool
category    string   "note"
perm        string   "owner" | ...
owner       {display_name, uid}
acl         {} | {enabled, public:{inherit, perm:"ro"}}
commit_msg  {} | {device, listable}   (last-edit metadata; field requested via field={commit_msg:true})
link_id     string   short public-link id (requested via field={link_id:true})
ver         string   content revision hash (sha1) — useful as sync/version key
thumb       null | {ext,height,width,md5,name,rotate,size,thumb_source,type:"image"}
```
NOTE: `content` and `tag` are NOT in the list response — content comes from `Note get`;
tag membership comes from `Tag list` (each tag lists its note ids in `items`).

## Notebook (SYNO.NoteStation.Notebook `list` v2 → `data.notebooks[]`, data.total)
```
object_id   string   THE NOTEBOOK ID  ← not notebook_id
title       string
stack       string   owning shelf/stack title ("" = none)  ← not stack_id
items       string[] ordered note object_ids → note count = items.length  ← not note_count
ctime/mtime int      epoch seconds
archive     bool     ← not "archived"
individual_shared bool  ← not "shared"
preset      bool     built-in notebook
link_id, ver, perm, owner, acl, category:"notebook"
```

## Tag (SYNO.NoteStation.Tag `list` v1 → data.tags[], data.total)
```
tag_id   string   "Name@uid" e.g. "Accounts@1026"   ← composite, not a ULID
title    string
items    string[] note object_ids carrying this tag
category "tag"
```

## Shortcut (SYNO.NoteStation.Shortcut `list` v1 → data.shortcuts[], data.total)
```
id       string   target object_id
category string   "note" (also notebook?)
title    string
items    null
owner, acl
```

## Todo (SYNO.NoteStation.Todo `list` v1 → data)
```
{count:0, offset:0, total:0}   ← was EMPTY in capture; no item shape observed yet.
Need a capture WITH at least one todo to learn item fields. (CAPTURE-CHECKLIST §2)
```

## Smart (SYNO.NoteStation.Smart `list` v1 → data)
```
{offset:0, total:0}   ← EMPTY in capture. Need a smart notebook created to learn shape.
```

## Cross-cutting
- IDs are `<volumeId>_<ULID>`; the per-object key is **`object_id`** everywhere (list
  responses), while write APIs take it as `object_id` too (see Note.Encrypt capture).
- `ver` (sha1) is a natural content-revision handle for sync/versioning.
- Timestamps are epoch **seconds** (×1000 for Dart DateTime).
