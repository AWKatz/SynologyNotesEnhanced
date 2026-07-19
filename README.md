# Synology Notes Enhanced

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
- **Rich-text notes** — renders Note Station's HTML content.
- **Client-side encryption** — reads password-protected notes by decrypting the
  `Salted__` / AES-256-CBC blob locally (the password never leaves the device).
- **`.nsx` import** — reads Note Station's ZIP-based export bundles.
- **Offline / local mode** — work with local notes without a NAS connection.
- **Session persistence** — credentials stored via the platform secure store.

Some capabilities (attachment upload, version history, sharing, more export/import
formats) are still in progress — see the API mapping below for current status.

## Reverse-engineering the API

Because Note Station has no official API, everything here is reconstructed from observed
behavior. The [`docs/api/`](docs/api/) folder is the working specification:

- **[docs/api/NoteStation API documentation.md](<docs/api/NoteStation API documentation.md>)**
  — the complete API reference: every `SYNO.NoteStation.*` method/param/response, the wire
  conventions, verified object schemas, the client-side note-encryption scheme, and the
  `.nsx` export format, each tagged **verified by live capture** or **inferred**.
- **[docs/api/captures/](docs/api/captures/)** — annotated (secrets-redacted) request/
  response captures from the stock web client that serve as ground truth.
- **[docs/api/CAPTURE-CHECKLIST.md](docs/api/CAPTURE-CHECKLIST.md)** — what to click in
  the web UI to capture the APIs still missing.

Contributions of new captures and corrections are especially welcome — the more real
traffic we document, the more complete the client becomes.

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
