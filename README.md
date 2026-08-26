# Synology Notes Enhanced
<img width="951" height="618" alt="Screenshot 2026-07-31 182826" src="https://github.com/user-attachments/assets/243881f8-6acd-4ab5-b99c-162f545e71b7" />

A feature-rich, open-source alternative to Synology's **DS Notes** client for
[Note Station](https://www.synology.com/en-global/dsm/feature/note_station) — built with
Flutter and running on **Android, iOS, Windows, macOS, and Linux**.

The goal is twofold:

1. **A better Note Station client.** DS Notes is functional but limited and no longer
   actively developed. This project aims for a faster, cleaner, cross-platform client
   with the features power users actually want.
2. **A documented Note Station API.** Synology has never published a public API for
   Note Station, so this project also serves as an ongoing effort to **reverse-engineer
   and document** the `SYNO.NoteStation.*` web APIs and the `.nsx` export format, so that
   others can build against them too.

> ⚠️ **Unofficial.** This project is not affiliated with, endorsed by, or supported by
> Synology Inc. "Synology", "DiskStation", "DSM", and "Note Station" are trademarks of
> Synology Inc. Use at your own risk.

## Features

- **Cross-platform** — one codebase for mobile and desktop.
- **Browse & edit** notebooks, notes, tags, and shelves backed by the live Note Station API.
- **Rich-text notes** — renders Note Station's HTML content, with in-app WebView editing for
  notes that use a confirmed-safe formatting subset (fidelity-first: anything outside it stays
  read-only rather than risk silently stripping formatting on save — see `rich_html_schema.dart`).
- **To-do lists** — create, check off, set due dates and priority.
- **Smart notebooks** — saved-search notebooks with criteria-based matching.
- **Trash** — move notes to trash, restore, or permanently purge.
- **Version history** — browse and restore a note's prior saved versions.
- **Sharing & permissions** — public share links and per-user/per-group permissions.
- **Client-side encryption** — reads password-protected notes by decrypting the
  `Salted__` / AES-256-CBC blob locally (the password never leaves the device).
- **`.nsx` import/export** — both a local ZIP codec (works fully offline) and the NAS's own
  server-side export/import job.
- **Offline / local mode** — work with local notes without a NAS connection.
- **Session persistence** — credentials stored via the platform secure store.

Working toward full parity with the stock DS Note client — see the API coverage table below
for exactly what's implemented versus still open, kept up to date as features land.

## NoteStation API coverage

Synology has never published a spec for `SYNO.NoteStation.*`, so this project also
reverse-engineers it from real client/server traffic as it goes. Working today (implemented
and wired into the app, not just verified by capture):

| Area | What works |
|---|---|
| Auth | Login/logout, 2FA (OTP) type discovery |
| Shelves | List |
| Notebooks | List, create, rename, delete |
| Notes | List, get, create, edit, move to trash, restore, permanently purge, full-text search |
| Rich-text editing | In-app WebView editor for the confirmed-safe HTML subset; everything else renders read-only |
| Attachments/images | Upload (embedded in a note save) and download/render inline |
| Encryption | Client-side AES-256-CBC password-protect / unlock, fully local — DSM never sees a plaintext password or content |
| Tags | List, create |
| To-do lists | List, create, edit, delete, due dates, priority |
| Smart notebooks | List, create, criteria-based note matching |
| Version history | List a note's versions, restore a prior version |
| Sharing & permissions | Public share link, per-user/per-group permission grants |
| `.nsx` | Import and export, both a local ZIP codec (no server round-trip) and the NAS's own server-side export/import job |

Not yet implemented: **DSM-side import of non-`.nsx` formats** (the server-side import job
only handles `.nsx`; other formats DSM's own client may support, e.g. Evernote, aren't wired
up), **audio note attachments** (the attachment picker is image-only; DS Note supports
recording/attaching audio), and **to-do due-date reminders/notifications** (due dates are
stored and shown, but nothing schedules a local or push reminder). Verified via live capture
but deliberately **not** used by the app: batch startup sync (`SYNO.Entry.Request` — the app
makes its calls individually instead), DSM's own sidebar-shortcuts sync, and server-side
view/sort preference sync (kept local instead, by design).

**[`.docs/NoteStation API documentation.md`](<.docs/NoteStation API documentation.md>)** is
the complete, maintained reference behind the table above — every method/param/response
shape, wire conventions, the object schemas, the note-encryption scheme, and the `.nsx`
format, each tagged **verified by live capture** or **inferred**. It's the one file from this
project's internal `.docs/` working notes that's tracked in git and shipped publicly; the
raw (redacted) traffic captures behind it are kept as private local working material and
aren't shipped, since even redacted real NAS traffic isn't something to publish by default.

Contributions of new capture evidence and corrections are especially welcome — open an issue
or PR with the redacted request/response and what you observed; the more real traffic gets
documented, the more complete both the client and the spec become.

## Getting started

```bash
flutter pub get
flutter run
```

To connect, enter your NAS host/IP, port, and account in the login screen — or choose
**local mode** to work offline. Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(Dart `>=3.3.0`).

## Contributing

Issues and pull requests are welcome — whether that's app features, bug fixes, or new/
corrected API captures. Please don't commit any real credentials, session tokens, or
personal NAS hostnames in captures; redact them the way the existing files do.

## License

Licensed under the **GNU Affero General Public License v3.0** — see [LICENSE](LICENSE).

In short: you're free to use, modify, and share this software, but any distributed or
**network-hosted** derivative must also be released as open source under the AGPLv3. This
keeps the project open and prevents it from being turned into a closed-source or
proprietary paid product.
