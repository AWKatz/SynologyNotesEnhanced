# Rich-text editor — design direction

Goal: OneNote-class formatting (fonts, styling, layouts, tables, embeds) **without**
breaking interop with the stock Note Station app or `.nsx` export/import.

## Decision (2026-06-21): fidelity-first

The editor's internal document model is **HTML constrained to the subset NoteStation
preserves on save**. The editor must be unable to emit constructs the stock app would
strip. This rules out flutter_quill as the primary editor — its Delta model is not HTML
and the HTML round-trip is lossy.

**Chosen architecture:** WebView-hosted **ProseMirror / TipTap** editor with a custom
schema mapped 1:1 to NoteStation's allowed HTML. Flutter ↔ WebView bridge passes HTML in
and out; Flutter owns toolbar/chrome where we want native feel.

Rationale: ProseMirror's schema is the enforcement mechanism — anything not in the schema
can't exist in the document, guaranteeing the saved HTML stays within the safe subset.

## BLOCKER: we don't yet know NoteStation's stored HTML schema

`createNote` sends `<p></p>`, so content is HTML — but we don't know which tags,
attributes, and inline styles survive a server save. This defines the entire ProseMirror
schema. **Must capture before building.**

### Capture task (added to CAPTURE-CHECKLIST.md)
1. In the stock web client, create a note and apply *everything*: headings, bold/italic/
   underline/strike, colored text, highlight, font family + size, bullet/numbered/nested
   lists, checkboxes, a table, an image, a link, code block, blockquote, indentation,
   alignment.
2. Save, reload, and capture `Note get` (`include_content=true`) →
   `captures/Note.get.formatted.txt`.
3. From the returned `content`, document the exact preserved tag/attr/style vocabulary in
   `docs/api/NoteStation-HTML-schema.md`. Note especially: are colors/fonts inline
   `style=""` or classes? Are tables real `<table>`? How are checkboxes encoded? How are
   images referenced (data URI vs attachment ref id)?

## Build sequence (after schema is known)
1. Define ProseMirror schema = preserved subset. Anything richer than the subset must
   degrade gracefully to something preserved.
2. WebView editor + Flutter bridge (load HTML, emit HTML on change/blur, autosave hook).
3. Native Flutter toolbar driving editor commands over the bridge.
4. Image/attachment flow ties into `SYNO.FileStation.Upload` (P1 attachments work).
5. Validate round-trip: edit in our app → open in stock app → confirm no loss, and v.v.

## Open questions
- Anything our schema allows that the stock app strips = data loss. The capture is how we
  find the boundary; a round-trip test is how we keep it honest.
- "Modern layouts" beyond NoteStation's vocabulary (multi-column, free positioning) may be
  impossible to store losslessly. Decide per-feature: degrade-on-save vs. drop.
