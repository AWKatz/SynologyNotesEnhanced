# SYNO.NoteStation.Todo

Versions: 1–2 · Status: 📝 inferred, needs capture · Feature: tasks / to-do list

Powers the to-do list: tasks classified as starred / overdue / due-within-7-days, with
priority, scheduling, DSM-notification reminders, and subtasks. A note may hold up to 50
tasks (per `requirements.txt`), so todos are both standalone objects and embedded in note
content. **Open question to settle via capture:** are todos first-class objects with their
own IDs, or always children of a note? The capture for `list` will answer this.

## Methods (inferred — verify all)

### `list` — all todos for the user
Params (likely):
- `version = 2`
- *(maybe)* `notebook_id = <id>` to scope
- *(maybe)* `filter = all | starred | overdue | due7` — the UI's four buckets

Expected response: `{ todos: [ { todo_id, title, done, priority, due_date, reminder,
note_id, parent_id?, mtime, ctime } ] }`  ← field names are guesses.

### `create`
Params (likely): `title`, `note_id?`, `due_date?`, `priority?`, `parent_id?` (for subtask).

### `update`
Params (likely): `todo_id`, plus any of `title`, `done`/`is_done`, `priority`,
`due_date`, `reminder`, `is_starred`.

### `delete`
Params (likely): `todo_id`.

## Unknowns to confirm in capture
1. Object key name: `todo_id` vs `object_id`.
2. Done flag name: `done` vs `is_done` vs `status`.
3. Date format: epoch seconds vs ms vs ISO string. (Note APIs here use epoch seconds.)
4. How subtasks are linked (`parent_id`?) and the 50-per-note cap enforcement.
5. Reminder representation (epoch + DSM notification id?).

## Capture steps
See `CAPTURE-CHECKLIST.md` § Todo. Minimum: create a task, star it, set a due date,
add a subtask, mark done, delete — one DevTools entry each.
