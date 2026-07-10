# Capture checklist

How to turn an unknown API into a verified spec. Do this against the **stock Note Station
web client** on your NAS, with browser DevTools open.

## Setup (once)

1. Log into DSM, open **Note Station** in the browser.
2. Open DevTools → **Network** tab. Filter to `entry.cgi`.
3. Tick **Preserve log**. Leave it recording.
4. Perform one action at a time (below). For each, click the `entry.cgi` row →
   - **Payload** tab → copy the form data (the `api=…&method=…` body).
   - **Response** tab → copy the JSON.
5. Save as `captures/<Api>.<action>.txt` in the format of `captures/Note.Encrypt.txt`:
   ```
   Request:
   <decoded form body>

   Response:
   <json>
   ```
6. Tell me which files you added — I'll turn them into the verified spec + Dart methods.

> Tip: right-click the request → **Copy → Copy as cURL** captures everything unambiguously
> (including how values are quoted). Paste that if unsure.

## Priority order

### 1. Sync (highest value — do first)
- [ ] Open Note Station, then **sit idle ~60s** with Network recording → catch the
      automatic background **poll**. Save `captures/Note.Polling.idle.txt`.
- [ ] In a second tab, edit a note's title, save. Back in tab 1, capture the next poll →
      `captures/Note.Polling.afterchange.txt`.
- [ ] Delete a note; capture the poll that reflects it → `captures/Note.Polling.delete.txt`.
- [ ] Rename a notebook; capture → `captures/Notebook.Polling.txt`.

### 1b. Stored HTML schema (blocks the rich-text editor — see docs/RICH-TEXT.md)
- [ ] Create one note in the stock web client, apply *everything* (headings, bold/italic/
      underline/strike, text color, highlight, font family + size, bullet/numbered/nested
      lists, checkboxes, table, image, link, code block, blockquote, indent, alignment),
      save, reload, then capture `Note get` with `include_content=true` →
      `captures/Note.get.formatted.txt`. This defines the ProseMirror schema.

### 2. Todo
- [ ] Open the to-do list view → `captures/Todo.list.txt`
- [ ] Create a task → `captures/Todo.create.txt`
- [ ] Star it; set a due date; set priority → `captures/Todo.update.txt`
- [ ] Add a subtask → `captures/Todo.subtask.txt`
- [ ] Mark done; then delete → `captures/Todo.done-delete.txt`

### 3. Smart notebooks
- [ ] Create a smart notebook with a couple of criteria → `captures/Smart.create.txt`
      (this one is critical — it reveals how nested/array params are encoded on the wire).
- [ ] List smart notebooks; open one → `captures/Smart.list.txt`

### 4. Attachments
- [ ] Drag an image into a note → `captures/FileStation.Upload.txt`
- [ ] Reopen the note, load the attachment → `captures/FileStation.Download.txt`

### Later (P2+)
- [ ] Restore an old version → `captures/Note.Version.txt`
- [ ] Share a note to a DSM user → `captures/Share.Priv.txt`
- [ ] Create a public link → `captures/Shard.txt`
- [ ] Export a notebook as .nsx → `captures/Export.Notebook.txt`
- [ ] Import a .nsx → `captures/Import.Notebook.txt`
- [ ] Move a note to trash / restore → `captures/Note.Ghost.txt`

## What I do with each capture
Decode the body → fill methods/params/response in the matching `SYNO.*.md` spec, flip its
status to ✅ V in `README.md`, then add the typed method to `note_station_service.dart`
(after the central param-encoding fix in `_CONVENTIONS.md`).
