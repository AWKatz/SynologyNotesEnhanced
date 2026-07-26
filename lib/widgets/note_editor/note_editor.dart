import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import '../../core/crypto/note_crypto.dart';
import '../../core/rich_html/rich_html_schema.dart';
import '../../models/note.dart';
import '../../providers/app_mode_provider.dart' show repositoryProvider;
import '../../providers/note_color_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/notebooks_provider.dart';
import '../../providers/api_provider.dart';
import '../../providers/tags_provider.dart';
import '../common/app_toast.dart';
import 'rich_html_editor.dart';

class NoteEditor extends ConsumerWidget {
  const NoteEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final noteAsync = ref.watch(selectedNoteProvider);

    return noteAsync.when(
      loading: () => Container(
        color: cs.surface,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Container(
        color: cs.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Failed to load note',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => ref.invalidate(selectedNoteProvider),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (note) {
        if (note == null) return const _NoNoteSelected();
        return _NoteEditorContent(note: note);
      },
    );
  }
}

class _NoteEditorContent extends ConsumerStatefulWidget {
  final Note note;
  const _NoteEditorContent({required this.note});

  @override
  ConsumerState<_NoteEditorContent> createState() => _NoteEditorContentState();
}

class _NoteEditorContentState extends ConsumerState<_NoteEditorContent> {
  final _titleController = TextEditingController();
  final _richEditorKey = GlobalKey<RichHtmlEditorState>();
  bool _isDirty = false;
  bool _editing = false;

  // Encrypted notes: decrypted HTML once the user unlocks (read-only).
  String? _decryptedHtml;

  // Rich editor's own image-resolved HTML (data: URIs — see
  // _resolveImagesForEditor), fetched once when entering edit mode. Null
  // means "no images to fetch" (the common case) or "not entered edit mode
  // since this note loaded yet" — _buildRichEditor falls back to
  // _resolveImages in either case.
  String? _richEditorHtml;
  bool _preparingEditor = false;

  // Images inserted since the last save, keyed by the `ref` embedded in
  // their (not-yet-uploaded) <img> tag — drained by _saveNote via
  // NoteStationService.uploadNoteAttachment. Reset in _loadNote alongside
  // everything else scoped to whichever note is currently open.
  final _pendingImages = <String, ({String fileName, List<int> bytes})>{};

  // Debug aid: which (note id, ver) we last logged an image-resolution
  // diagnostic for, so _resolveImages logs once per save/reload instead of
  // once per rebuild. See _resolveImages.
  String? _lastLoggedImageDebugKey;

  bool get _isEncrypted =>
      widget.note.isEncrypted || NoteCrypto.isEncrypted(widget.note.content);

  /// HTML to display: decrypted body for encrypted notes, else the raw content.
  String get _displayHtml => _decryptedHtml ?? widget.note.content;

  /// Display HTML with NoteStation's checkbox `<input type="image">` markers
  /// (which point at an unreachable relative gif) swapped for plain glyphs,
  /// and real image `<img ref="...">` tags resolved to an authenticated
  /// display URL (see [_resolveImages]).
  String get _renderHtml => _resolveImages(_displayHtml)
      .replaceAll(
          RegExp(r'<input[^>]*checkbox-checked[^>]*>', caseSensitive: false),
          '&#9745; ')
      .replaceAll(
          RegExp(r'<input[^>]*syno-notestation-editor-checkbox[^>]*>',
              caseSensitive: false),
          '&#9744; ');

  /// Rewrites `<img ... ref="X" ... />` tags to carry a real, authenticated
  /// display URL in `src` instead of the saved placeholder — the image
  /// equivalent of the checkbox-glyph substitution above.
  ///
  /// CONFIRMED (2026-07-25, live NAS note): the client-generated `ref` an
  /// image is inserted with is never corrected to the server's real
  /// attachment-map key on save — `ref="MTc4NTAwODU5MzE1MlNORSgxKS5wbmc="`
  /// (base64 of `1785008593152SNE(1).png`, a timestamp+filename) round-
  /// tripped alongside an `attachment` map keyed
  /// `"_O-JRTSy0kxnSpQUvqXDkoA"` — an unrelated opaque server ID. So a
  /// literal `ref` → map-key lookup can never succeed. Since there's no
  /// decodable relationship between the two, this pairs each `ref` (in
  /// document order) with an attachment entry (in map/JSON order) that no
  /// earlier `ref` already claimed — correct whenever images were inserted
  /// and never reordered relative to their attachment entries, which is the
  /// only correlation available without more capture data. A `ref` left
  /// unpaired (more images than attachment entries), or a note missing
  /// `linkId`/`ver` entirely, is left as-is (still shows the transparent
  /// placeholder, same as before this feature existed — never worse).
  String _resolveImages(String html) {
    final client = ref.read(apiClientProvider);
    // .watch (not .read): the ticket arrives asynchronously after the note
    // first renders, and this provider is what triggers the rebuild that
    // resolves images once it lands.
    final tid = ref.watch(noteImageTidProvider).valueOrNull;
    final linkId = widget.note.linkId;
    final ver = widget.note.ver;

    final refsInHtml = RegExp(r'<img\b[^>]*\bref="([^"]*)"',
            caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();

    final shouldLog = refsInHtml.isNotEmpty &&
        _lastLoggedImageDebugKey != '${widget.note.id}@$ver@$tid';
    if (shouldLog) _lastLoggedImageDebugKey = '${widget.note.id}@$ver@$tid';
    if (client == null || linkId == null || ver == null || tid == null) {
      if (shouldLog) {
        debugPrint('Note ${widget.note.id} image resolution: '
            'linkId=$linkId ver=$ver tid=$tid refs-in-html=$refsInHtml '
            '(client=${client != null})');
      }
      return html;
    }

    final refToKey = _refToAttachmentKey(refsInHtml);

    if (shouldLog) {
      final resolved = {
        for (final r in refsInHtml)
          r: refToKey[r] == null
              ? 'UNMATCHED'
              : client
                  .noteImageUri(
                    linkId: linkId,
                    ver: ver,
                    attachmentKey: refToKey[r]!,
                    fileName: (widget.note.attachment[refToKey[r]!]
                            as Map<String, dynamic>?)?['name'] as String? ??
                        refToKey[r]!,
                    tid: tid,
                  )
                  .toString(),
      };
      debugPrint('Note ${widget.note.id} image resolution: '
          'linkId=$linkId ver=$ver refs-in-html=$refsInHtml '
          'attachment-keys=${widget.note.attachment.keys.toList()} '
          'resolved=$resolved');
    }

    return html.replaceAllMapped(
      RegExp(r'<img\b[^>]*\bref="([^"]*)"[^>]*/?>', caseSensitive: false),
      (match) {
        final imgRef = match.group(1)!;
        final key = refToKey[imgRef];
        if (key == null) return match.group(0)!;
        final meta = widget.note.attachment[key] as Map<String, dynamic>?;
        if (meta == null) return match.group(0)!;
        final fileName = meta['name'] as String? ?? key;
        final uri = client.noteImageUri(
          linkId: linkId,
          ver: ver,
          attachmentKey: key,
          fileName: fileName,
          tid: tid,
        );
        // Only swap `src` — every other attribute (class/ref/border/adjust)
        // must survive untouched for the next save to still round-trip.
        return match.group(0)!.replaceFirst(
            RegExp(r'src="[^"]*"', caseSensitive: false), 'src="$uri"');
      },
    );
  }

  /// Pairs each `ref` found in a note's HTML with an attachment-map key —
  /// shared by [_resolveImages] and [_resolveImagesForEditor]. See
  /// [_resolveImages]'s doc comment for why literal matches almost never
  /// happen and positional pairing is the fallback.
  Map<String, String> _refToAttachmentKey(List<String> refsInHtml) {
    final claimedKeys = refsInHtml
        .where((r) => widget.note.attachment.containsKey(r))
        .toSet();
    final unclaimedKeys = widget.note.attachment.keys
        .where((k) => !claimedKeys.contains(k))
        .toList();
    var nextUnclaimed = 0;
    final refToKey = <String, String>{};
    for (final r in refsInHtml) {
      if (widget.note.attachment.containsKey(r)) {
        refToKey[r] = r;
      } else if (nextUnclaimed < unclaimedKeys.length) {
        refToKey[r] = unclaimedKeys[nextUnclaimed++];
      }
    }
    return refToKey;
  }

  /// Like [_resolveImages], but for the rich editor's WebView specifically:
  /// fetches each image's bytes through SynologyApiClient's own cert-
  /// trusting HTTP client and embeds them as `data:` URIs, instead of
  /// pointing `src` at a remote `https://` URL. Needed because the WebView
  /// is a separate network stack (Chromium/WebView2) that kept failing to
  /// load images from this NAS's self-signed/hostname-mismatched cert even
  /// after wiring up its own server-trust handler — see
  /// SynologyApiClient.fetchBytes's doc comment. A `data:` URI needs no
  /// network request at all once fetched, sidestepping the problem
  /// entirely — the same trick already used for a not-yet-saved inserted
  /// image's live preview.
  Future<String> _resolveImagesForEditor(String html) async {
    final client = ref.read(apiClientProvider);
    final linkId = widget.note.linkId;
    final ver = widget.note.ver;
    final refsInHtml = RegExp(r'<img\b[^>]*\bref="([^"]*)"',
            caseSensitive: false)
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
    if (client == null || linkId == null || ver == null || refsInHtml.isEmpty) {
      return html;
    }

    final tid = ref.read(noteImageTidProvider).valueOrNull ??
        await ref.read(noteImageTidProvider.future);
    if (tid == null) return html;
    final refToKey = _refToAttachmentKey(refsInHtml);

    final refToDataUri = <String, String>{};
    for (final r in refsInHtml) {
      final key = refToKey[r];
      final meta =
          key == null ? null : widget.note.attachment[key] as Map<String, dynamic>?;
      if (key == null || meta == null) continue;
      final fileName = meta['name'] as String? ?? key;
      final uri = client.noteImageUri(
        linkId: linkId,
        ver: ver,
        attachmentKey: key,
        fileName: fileName,
        tid: tid,
      );
      try {
        final bytes = await client.fetchBytes(uri);
        refToDataUri[r] =
            'data:${_mimeTypeFor(fileName)};base64,${base64Encode(bytes)}';
      } catch (e) {
        debugPrint('Failed to fetch image bytes for editor ($r): $e');
      }
    }

    return html.replaceAllMapped(
      RegExp(r'<img\b[^>]*\bref="([^"]*)"[^>]*/?>', caseSensitive: false),
      (match) {
        final dataUri = refToDataUri[match.group(1)];
        if (dataUri == null) return match.group(0)!;
        return match.group(0)!.replaceFirst(
            RegExp(r'src="[^"]*"', caseSensitive: false), 'src="$dataUri"');
      },
    );
  }

  /// Notes using only the confirmed-preserved HTML vocabulary (see
  /// rich_html_schema.dart) get the rich WebView editor — including plain
  /// notes, since unformatted text trivially satisfies the schema too, and
  /// routing them here (rather than a separate plain-text field) is what
  /// lets a plain note gain formatting. Links, images, and text-align now
  /// count as confirmed too (2026-07-25 HAR capture); anything still outside
  /// the vocabulary (code blocks, blockquotes, ...) stays read-only, same as
  /// before this editor existed — fidelity-first, per docs/RICH-TEXT.md.
  bool get _isEditable =>
      !_isEncrypted && RichHtmlSchema.isRoundTrippable(_displayHtml);

  @override
  void initState() {
    super.initState();
    _loadNote(widget.note);
  }

  @override
  void didUpdateWidget(_NoteEditorContent old) {
    super.didUpdateWidget(old);
    if (old.note.id != widget.note.id) _loadNote(widget.note);
  }

  void _loadNote(Note note) {
    _titleController.text = note.title;
    _isDirty = false;
    _editing = false;
    _decryptedHtml = null;
    _pendingImages.clear();
    _richEditorHtml = null;
    if (!note.isEncrypted) {
      RichHtmlSchema.isRoundTrippable(note.content,
          onReject: (reason) => debugPrint(
              'Note ${note.id} ("${note.title}") not round-trippable, '
              'falling back to read-only: $reason'));
    }
  }

  /// Toggles edit mode. Turning it on, when the note has images, first
  /// awaits _resolveImagesForEditor so the WebView opens with real pictures
  /// already embedded as data: URIs rather than placeholders it can't
  /// resolve on its own — see that method's doc comment. Skipped entirely
  /// for the common case (no images), so most notes toggle instantly.
  Future<void> _toggleEdit() async {
    if (_editing) {
      setState(() => _editing = false);
      return;
    }
    if (!RegExp(r'<img\b[^>]*\bref=').hasMatch(_displayHtml)) {
      setState(() => _editing = true);
      return;
    }
    setState(() => _preparingEditor = true);
    final resolved = await _resolveImagesForEditor(_displayHtml);
    if (!mounted) return;
    setState(() {
      _richEditorHtml = resolved;
      _editing = true;
      _preparingEditor = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (!_isDirty) return;
    final service = ref.read(noteStationServiceProvider);
    if (service == null) {
      AppToast.error(context, 'Saving isn\'t available in offline mode yet.');
      return;
    }

    try {
      // Data-loss guard: only write a body when the rich editor is actually
      // mounted. Encrypted/unconfirmed-schema notes never get a content
      // write here — they aren't reachable in an editing state.
      String? content;
      if (_isEditable) {
        content = await _richEditorKey.currentState?.getContent();
      }

      if (_pendingImages.isNotEmpty && content != null) {
        // Each upload is itself a complete Note.set (see
        // uploadNoteAttachment's doc comment) — loop so every image
        // inserted since the last save persists, threading the freshest
        // `ver` each call returns into the next one.
        var current = widget.note;
        for (final entry in Map.of(_pendingImages).entries) {
          current = await service.uploadNoteAttachment(
            note: current,
            content: content,
            fileName: entry.value.fileName,
            fileBytes: entry.value.bytes,
            ref: entry.key,
          );
        }
        _pendingImages.clear();
        if (_titleController.text != widget.note.title) {
          await service.updateNote(
              noteId: current.id, title: _titleController.text);
        }
      } else {
        await service.updateNote(
          noteId: widget.note.id,
          title: _titleController.text,
          content: content,
        );
      }

      if (mounted) {
        setState(() {
          _isDirty = false;
          _editing = false;
        });
        AppToast.success(context, 'Note saved');
      }
      syncAfterMutation(ref);
    } catch (e) {
      debugPrint('Save note failed: $e');
      if (mounted) AppToast.error(context, 'Could not save the note.');
    }
  }

  /// Picks an image, inserts an optimistic live-preview into the rich
  /// editor immediately, and stashes the bytes for _saveNote to actually
  /// upload — mirrors how every other toolbar action here only takes effect
  /// on Save (see NoteStationService.uploadNoteAttachment's doc comment for
  /// why upload can't just happen right away).
  Future<void> _insertImage() async {
    final picked =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;

    final fileName = file.name;
    final bytes = file.bytes!;
    // Matches the capture's own pattern (base64 of epoch-ms + filename) — a
    // simple, collision-resistant id; it doesn't need to match Synology's
    // own generation algorithm exactly, just be unique per upload.
    final imgRef = base64Encode(
        utf8.encode('${DateTime.now().millisecondsSinceEpoch}$fileName'));
    final dataUri =
        'data:${_mimeTypeFor(fileName)};base64,${base64Encode(bytes)}';

    _pendingImages[imgRef] = (fileName: fileName, bytes: bytes);
    await _richEditorKey.currentState?.insertImage(dataUri, imgRef);
    if (!_isDirty && mounted) setState(() => _isDirty = true);
  }

  static String _mimeTypeFor(String fileName) {
    switch (fileName.split('.').last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final noteColor = ref.watch(noteColorsProvider)[widget.note.id];
    final colorStrip = noteColor == null
        ? const SizedBox.shrink()
        : Container(height: 4, color: noteColor);

    // Gate encrypted notes behind a password prompt until unlocked.
    if (_isEncrypted && _decryptedHtml == null) {
      return Container(
        color: cs.surface,
        child: Column(
          children: [
            colorStrip,
            _EditorMeta(note: widget.note),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
              child: _EncryptedNoteGate(
                note: widget.note,
                onUnlocked: (html) => setState(() => _decryptedHtml = html),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          colorStrip,
          _EditorToolbar(
            note: widget.note,
            isDirty: _isDirty,
            editing: _editing,
            canEdit: _isEditable,
            isRichEditing: _editing && _isEditable,
            preparingEdit: _preparingEditor,
            richEditorKey: _richEditorKey,
            onSave: _saveNote,
            onToggleEdit: _toggleEdit,
            onInsertImage: _insertImage,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          _EditorMeta(note: widget.note),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _editing && _isEditable
                ? _buildRichEditor(context, cs)
                : _buildReadView(context, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildRichEditor(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
          child: TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
            decoration: const InputDecoration(
              hintText: 'Note title',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => setState(() => _isDirty = true),
          ),
        ),
        Expanded(
          child: RichHtmlEditor(
            key: _richEditorKey,
            initialHtml: _richEditorHtml ?? _resolveImages(_displayHtml),
            darkMode: Theme.of(context).brightness == Brightness.dark,
            accentColor: Theme.of(context).colorScheme.primary,
            onDirty: () {
              if (!_isDirty) setState(() => _isDirty = true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReadView(BuildContext context, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.note.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
          ),
          const SizedBox(height: 16),
          if (_displayHtml.trim().isEmpty)
            Text('This note is empty.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14))
          else
            // ExcludeSemantics works around Flutter framework assertions
            // (_RenderObjectSemantics.debugCheckForParentData/debugCheckForBuilds)
            // triggered by flutter_widget_from_html_core's inline WidgetSpans
            // (checkbox images, <hr>, tables). Upgrading to 0.17.x (see
            // pubspec.yaml) fixed the parentDataDirty case but NOT this one
            // (debugCheckForBuilds / 'node.built') — confirmed still crashing
            // pre-upgrade-style content in real use, so keep this workaround.
            ExcludeSemantics(
              child: HtmlWidget(
                _renderHtml,
                textStyle:
                    TextStyle(fontSize: 15, color: cs.onSurface, height: 1.6),
              ),
            ),
          if (!_isEditable && !_isEncrypted) ...[
            const SizedBox(height: 24),
            _RichReadOnlyBanner(cs: cs),
          ],
        ],
      ),
    );
  }
}

/// Read-only notice shown under richly-formatted notes (which we render but
/// don't yet let users edit in-app, to avoid clobbering their formatting).
class _RichReadOnlyBanner extends StatelessWidget {
  final ColorScheme cs;
  const _RichReadOnlyBanner({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This note has rich formatting. In-app editing is read-only for '
              'now to preserve it — edit in the Synology app meanwhile.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Password prompt + client-side decryption for an encrypted note.
class _EncryptedNoteGate extends ConsumerStatefulWidget {
  final Note note;
  final ValueChanged<String> onUnlocked;
  const _EncryptedNoteGate({required this.note, required this.onUnlocked});

  @override
  ConsumerState<_EncryptedNoteGate> createState() => _EncryptedNoteGateState();
}

class _EncryptedNoteGateState extends ConsumerState<_EncryptedNoteGate> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The list/get content may be a snippet; fetch the full encrypted body.
      var content = widget.note.content;
      if (!NoteCrypto.isEncrypted(content)) {
        final service = ref.read(noteStationServiceProvider);
        if (service != null) {
          content = (await service.getNote(widget.note.id)).content;
        }
      }
      final html = NoteCrypto.decrypt(content, password);
      if (mounted) widget.onUnlocked(html);
    } on WrongPasswordException {
      if (mounted) setState(() => _error = 'Incorrect password.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not unlock this note.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text('Encrypted note',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('Enter the password to view “${widget.note.title}”.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                autofocus: true,
                onSubmitted: (_) => _unlock(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  isDense: true,
                  errorText: _error,
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _unlock,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.lock_open_rounded, size: 16),
                  label: const Text('Unlock'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sets a password on a currently-plain note. NAS mode: this creates a NEW
/// note object (verified — see Note.Encrypt.write.txt, the stock client's
/// `Note.copy`-based encrypt) and trashes the plaintext original, so the
/// note actually being viewed changes id; the caller must re-point selection
/// at the returned note.
class _EncryptNoteDialog extends ConsumerStatefulWidget {
  final Note note;
  const _EncryptNoteDialog({required this.note});

  @override
  ConsumerState<_EncryptNoteDialog> createState() => _EncryptNoteDialogState();
}

class _EncryptNoteDialogState extends ConsumerState<_EncryptNoteDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    if (password != _confirmController.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (repo == null) return;
      final encrypted =
          await repo.encryptNote(note: widget.note, password: password);
      // NAS mode returns a new note id (the old one was trashed) — follow it.
      ref.read(selectedNoteIdProvider.notifier).state = encrypted.id;
      syncAfterMutation(ref);
      if (mounted) {
        AppToast.success(context, 'Note encrypted');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Encrypt note failed: $e');
      if (mounted) setState(() => _error = 'Could not encrypt this note.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Encrypt Note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Set a password for "${widget.note.title}". You will need it to '
            'view this note again — there is no recovery if you forget it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              isDense: true,
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Encrypt'),
        ),
      ],
    );
  }
}

/// One-off swatch picker for applying a text/highlight color to the current
/// rich-editor selection — distinct from note_color_provider's persisted
/// per-note color labels; this is a live formatting action, not saved state.
Future<Color?> _pickColor(BuildContext context) {
  return showDialog<Color>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Color'),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: baseColorPalette
            .map((c) => InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).pop(c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                ))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// Prompts for a URL to wrap the current rich-editor selection in a link —
/// mirrors [_pickColor]'s one-off dialog pattern.
Future<String?> _promptLinkUrl(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Insert Link'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'URL',
          hintText: 'https://example.com',
          isDense: true,
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Insert'),
        ),
      ],
    ),
  );
}

/// Freeform px entry (plus quick presets) for text size — mirrors how
/// Word/Docs' font-size box works: type any value, or tap a common one.
/// Clamped to [6, 150] to match rich_html_schema.dart's _fontSizePx bound.
Future<int?> _promptFontSizePx(BuildContext context) {
  final controller = TextEditingController(text: '16');
  const presets = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72];

  int? clampedOrNull(String text) {
    final px = int.tryParse(text.trim());
    if (px == null) return null;
    return px.clamp(6, 150).toInt();
  }

  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Text Size'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Size (px)',
                isDense: true,
              ),
              onSubmitted: (v) => Navigator.of(context).pop(clampedOrNull(v)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final size in presets)
                  ActionChip(
                    label: Text('$size'),
                    onPressed: () => controller.text = '$size',
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(clampedOrNull(controller.text)),
          child: const Text('Apply'),
        ),
      ],
    ),
  );
}

/// Tap-or-drag grid for picking an Insert Table size (mirrors Word/Docs'
/// "Insert Table" picker) instead of always inserting a fixed 3x3 table.
/// A plain tap behaves like a zero-distance drag (onPanDown sets the hovered
/// cell, onPanEnd commits), so no separate tap handlers are needed.
class _TableSizePickerDialog extends StatefulWidget {
  const _TableSizePickerDialog();

  @override
  State<_TableSizePickerDialog> createState() =>
      _TableSizePickerDialogState();
}

class _TableSizePickerDialogState extends State<_TableSizePickerDialog> {
  static const int _maxRows = 6;
  static const int _maxCols = 8;
  static const double _cellSize = 28;
  static const double _cellGap = 4;

  int _hoverRows = 1;
  int _hoverCols = 1;

  void _updateFromLocalPosition(Offset local) {
    final col =
        (local.dx / (_cellSize + _cellGap)).ceil().clamp(1, _maxCols);
    final row =
        (local.dy / (_cellSize + _cellGap)).ceil().clamp(1, _maxRows);
    if (col != _hoverCols || row != _hoverRows) {
      setState(() {
        _hoverCols = col;
        _hoverRows = row;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Insert Table'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onPanDown: (d) => _updateFromLocalPosition(d.localPosition),
            onPanUpdate: (d) => _updateFromLocalPosition(d.localPosition),
            onPanEnd: (_) =>
                Navigator.of(context).pop((_hoverRows, _hoverCols)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < _maxRows; r++) ...[
                  if (r > 0) const SizedBox(height: _cellGap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < _maxCols; c++) ...[
                        if (c > 0) const SizedBox(width: _cellGap),
                        Container(
                          width: _cellSize,
                          height: _cellSize,
                          decoration: BoxDecoration(
                            color: r < _hoverRows && c < _hoverCols
                                ? cs.primary
                                : cs.surfaceContainerHigh,
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('$_hoverRows × $_hoverCols',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _EditorToolbar extends ConsumerWidget {
  final Note note;
  final bool isDirty;
  final bool editing;
  final bool canEdit;
  final bool isRichEditing;
  final bool preparingEdit;
  final GlobalKey<RichHtmlEditorState> richEditorKey;
  final VoidCallback onSave;
  final VoidCallback onToggleEdit;
  final Future<void> Function() onInsertImage;

  const _EditorToolbar({
    required this.note,
    required this.isDirty,
    required this.editing,
    required this.canEdit,
    required this.isRichEditing,
    required this.preparingEdit,
    required this.richEditorKey,
    required this.onSave,
    required this.onToggleEdit,
    required this.onInsertImage,
  });

  RichHtmlEditorState? get _rich => richEditorKey.currentState;

  Future<void> _pickAndApply(
      BuildContext context, ValueChanged<Color> apply) async {
    final color = await _pickColor(context);
    if (color != null) apply(color);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final noteColor = ref.watch(noteColorsProvider)[note.id];
    final noteColorLabel = noteColor == null
        ? null
        : ref.watch(colorLabelsProvider)[noteColor.toARGB32()];
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            // The formatting-button group can be wider than the toolbar at
            // narrower editor-panel widths (many buttons, several dividers,
            // two popup menus). Expanded + a horizontally-scrolling Row lets
            // it scroll internally instead of overflowing the fixed-height
            // pill — the trailing actions (save/edit/favorite/color/encrypt)
            // stay fixed and fully visible on the right regardless.
            if (editing && isRichEditing)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _ToolGroupButton(
                        icon: Icons.format_bold,
                        tooltip: 'Text formatting',
                        tools: [
                          _DropdownToolButton(
                              icon: Icons.format_bold,
                              tooltip: 'Bold',
                              onPressed: () => _rich?.bold()),
                          _DropdownToolButton(
                              icon: Icons.format_italic,
                              tooltip: 'Italic',
                              onPressed: () => _rich?.italic()),
                          _DropdownToolButton(
                              icon: Icons.format_underline,
                              tooltip: 'Underline',
                              onPressed: () => _rich?.underline()),
                          _DropdownToolButton(
                              icon: Icons.strikethrough_s_rounded,
                              tooltip: 'Strikethrough',
                              onPressed: () => _rich?.strikethrough()),
                          _DropdownToolButton(
                              icon: Icons.superscript_rounded,
                              tooltip: 'Superscript',
                              onPressed: () => _rich?.superscript()),
                          _DropdownToolButton(
                              icon: Icons.subscript_rounded,
                              tooltip: 'Subscript',
                              onPressed: () => _rich?.subscript()),
                          _DropdownToolButton(
                              icon: Icons.format_color_text_rounded,
                              tooltip: 'Text color',
                              onPressed: () => _pickAndApply(
                                  context, (c) => _rich?.fontColor(c))),
                          _DropdownToolButton(
                              icon: Icons.format_color_fill_rounded,
                              tooltip: 'Highlight',
                              onPressed: () => _pickAndApply(
                                  context, (c) => _rich?.highlight(c))),
                          _DropdownToolButton(
                              icon: Icons.format_size_rounded,
                              tooltip: 'Text size',
                              onPressed: () async {
                                final px = await _promptFontSizePx(context);
                                if (px != null) _rich?.fontSize(px);
                              }),
                        ],
                      ),
                      const _ToolbarDivider(),
                      PopupMenuButton<int>(
                        tooltip: 'Heading',
                        icon: Icon(Icons.title_rounded,
                            size: 18, color: cs.onSurfaceVariant),
                        onSelected: (level) => level == 0
                            ? _rich?.paragraph()
                            : _rich?.heading(level),
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 0, child: Text('Normal text')),
                          PopupMenuItem(value: 1, child: Text('Heading 1')),
                          PopupMenuItem(value: 2, child: Text('Heading 2')),
                          PopupMenuItem(value: 3, child: Text('Heading 3')),
                          PopupMenuItem(value: 4, child: Text('Heading 4')),
                          PopupMenuItem(value: 5, child: Text('Heading 5')),
                          PopupMenuItem(value: 6, child: Text('Heading 6')),
                        ],
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Align',
                        icon: Icon(Icons.format_align_left_rounded,
                            size: 18, color: cs.onSurfaceVariant),
                        onSelected: (direction) => _rich?.align(direction),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                              value: 'left',
                              child: Icon(Icons.format_align_left_rounded)),
                          PopupMenuItem(
                              value: 'center',
                              child: Icon(Icons.format_align_center_rounded)),
                          PopupMenuItem(
                              value: 'right',
                              child: Icon(Icons.format_align_right_rounded)),
                          PopupMenuItem(
                              value: 'justify',
                              child: Icon(Icons.format_align_justify_rounded)),
                        ],
                      ),
                      const _ToolbarDivider(),
                      PopupMenuButton<String>(
                        tooltip: 'Table',
                        icon: Icon(Icons.table_chart_outlined,
                            size: 18, color: cs.onSurfaceVariant),
                        onSelected: (action) async {
                          switch (action) {
                            case 'insert':
                              final size = await showDialog<(int, int)>(
                                context: context,
                                builder: (context) =>
                                    const _TableSizePickerDialog(),
                              );
                              if (size != null) {
                                _rich?.insertTable(
                                    rows: size.$1, cols: size.$2);
                              }
                            case 'row_above':
                              _rich?.tableInsertRowAbove();
                            case 'row_below':
                              _rich?.tableInsertRowBelow();
                            case 'col_left':
                              _rich?.tableInsertColumnLeft();
                            case 'col_right':
                              _rich?.tableInsertColumnRight();
                            case 'delete_row':
                              _rich?.tableDeleteRow();
                            case 'delete_col':
                              _rich?.tableDeleteColumn();
                            case 'delete_table':
                              _rich?.tableDeleteTable();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                              value: 'insert', child: Text('Insert table')),
                          PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'row_above',
                              child: Text('Insert row above')),
                          PopupMenuItem(
                              value: 'row_below',
                              child: Text('Insert row below')),
                          PopupMenuItem(
                              value: 'col_left',
                              child: Text('Insert column left')),
                          PopupMenuItem(
                              value: 'col_right',
                              child: Text('Insert column right')),
                          PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'delete_row', child: Text('Delete row')),
                          PopupMenuItem(
                              value: 'delete_col',
                              child: Text('Delete column')),
                          PopupMenuDivider(),
                          PopupMenuItem(
                              value: 'delete_table',
                              child: Text('Delete table')),
                        ],
                      ),
                      const _ToolbarDivider(),
                      _ToolGroupButton(
                        icon: Icons.add_circle_outline_rounded,
                        tooltip: 'Insert',
                        tools: [
                          _DropdownToolButton(
                              icon: Icons.format_list_bulleted,
                              tooltip: 'Bullet list',
                              onPressed: () => _rich?.unorderedList()),
                          _DropdownToolButton(
                              icon: Icons.format_list_numbered_rounded,
                              tooltip: 'Numbered list',
                              onPressed: () => _rich?.orderedList()),
                          _DropdownToolButton(
                              icon: Icons.check_box_outlined,
                              tooltip: 'Checkbox',
                              onPressed: () => _rich?.insertCheckbox()),
                          _DropdownToolButton(
                              icon: Icons.horizontal_rule_rounded,
                              tooltip: 'Divider',
                              onPressed: () => _rich?.insertDivider()),
                          _DropdownToolButton(
                              icon: Icons.link_rounded,
                              tooltip: 'Insert link',
                              onPressed: () async {
                                final url = await _promptLinkUrl(context);
                                if (url != null && url.isNotEmpty) {
                                  _rich?.insertLink(url);
                                }
                              }),
                          _DropdownToolButton(
                              icon: Icons.image_outlined,
                              tooltip: 'Insert image',
                              onPressed: () => onInsertImage()),
                        ],
                      ),
                      const _ToolbarDivider(),
                      _ToolGroupButton(
                        icon: Icons.crop_rounded,
                        tooltip: 'Image (tap a picture first)',
                        tools: [
                          _DropdownToolButton(
                              icon: Icons.format_align_left_rounded,
                              tooltip: 'Placement: left',
                              onPressed: () => _rich?.alignImage('left')),
                          _DropdownToolButton(
                              icon: Icons.format_align_center_rounded,
                              tooltip: 'Placement: center',
                              onPressed: () => _rich?.alignImage('center')),
                          _DropdownToolButton(
                              icon: Icons.format_align_right_rounded,
                              tooltip: 'Placement: right',
                              onPressed: () => _rich?.alignImage('right')),
                          _DropdownToolButton(
                              icon: Icons.photo_size_select_small_outlined,
                              tooltip: 'Size: small',
                              onPressed: () => _rich?.resizeImage('small')),
                          _DropdownToolButton(
                              icon: Icons.photo_size_select_large_outlined,
                              tooltip: 'Size: medium',
                              onPressed: () => _rich?.resizeImage('medium')),
                          _DropdownToolButton(
                              icon: Icons.photo_size_select_actual_outlined,
                              tooltip: 'Size: large',
                              onPressed: () => _rich?.resizeImage('large')),
                          _DropdownToolButton(
                              icon: Icons.crop_original_rounded,
                              tooltip: 'Size: original',
                              onPressed: () => _rich?.resizeImage('original')),
                          _DropdownToolButton(
                              icon: Icons.crop_square_rounded,
                              tooltip: 'Crop: square',
                              onPressed: () => _rich?.cropImage('square')),
                          _DropdownToolButton(
                              icon: Icons.crop_portrait_rounded,
                              tooltip: 'Crop: portrait',
                              onPressed: () => _rich?.cropImage('portrait')),
                          _DropdownToolButton(
                              icon: Icons.crop_landscape_rounded,
                              tooltip: 'Crop: landscape',
                              onPressed: () => _rich?.cropImage('landscape')),
                          _DropdownToolButton(
                              icon: Icons.crop_16_9_rounded,
                              tooltip: 'Crop: wide',
                              onPressed: () => _rich?.cropImage('wide')),
                          _DropdownToolButton(
                              icon: Icons.crop_free_rounded,
                              tooltip: 'Crop: none',
                              onPressed: () => _rich?.cropImage('none')),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
            if (editing && isDirty)
              TextButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            if (canEdit && preparingEdit)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (canEdit)
              _ToolbarButton(
                icon: editing ? Icons.check_rounded : Icons.edit_rounded,
                tooltip: editing ? 'Done' : 'Edit',
                color: editing ? cs.primary : null,
                onPressed: onToggleEdit,
              ),
            _ToolbarButton(
              icon: note.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              tooltip: note.isFavorite ? 'Unfavorite' : 'Favourite',
              color: note.isFavorite ? const Color(0xFFF59E0B) : null,
              onPressed: () async {
                final service = ref.read(noteStationServiceProvider);
                if (service == null) return;
                try {
                  await service.updateNote(
                    noteId: note.id,
                    isStarred: !note.isFavorite,
                  );
                  syncAfterMutation(ref);
                } catch (e) {
                  // Previously only invalidated notesProvider/
                  // selectedNoteProvider — not allNotesGlobalProvider, so
                  // the sidebar's Favorites count silently lagged behind
                  // an actual favorite/unfavorite until a manual sync.
                  debugPrint('Update favorite failed: $e');
                  if (context.mounted) {
                    AppToast.error(context, 'Could not update favorite.');
                  }
                }
              },
            ),
            _ToolbarButton(
              icon: noteColor != null
                  ? Icons.label_rounded
                  : Icons.label_outline_rounded,
              tooltip: noteColorLabel ?? 'Set Color',
              color: noteColor,
              onPressed: () => showColorPicker(context, ref,
                  id: note.id, colorsProvider: noteColorsProvider),
            ),
            if (!note.isEncrypted)
              _ToolbarButton(
                icon: Icons.lock_outline_rounded,
                tooltip: 'Encrypt Note',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => _EncryptNoteDialog(note: note),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditorMeta extends ConsumerWidget {
  final Note note;
  const _EditorMeta({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tagNames = ref.watch(tagNameMapProvider);
    final notebook = ref
        .watch(notebooksProvider)
        .valueOrNull
        ?.where((n) => n.id == note.notebookId)
        .firstOrNull;
    final updatedAt = note.updatedAt ?? note.createdAt;

    final resolvedTags = note.tags.map((id) => tagNames[id] ?? id).toList();

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.folder_rounded,
              size: 13, color: cs.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            notebook?.name ?? 'Unknown Notebook',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Icon(Icons.access_time_rounded, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            updatedAt != null
                ? DateFormat('MMM d, yyyy · HH:mm').format(updatedAt)
                : 'Unknown date',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (resolvedTags.isNotEmpty)
            Wrap(
              spacing: 4,
              children: resolvedTags
                  .map((t) => Chip(
                        label: Text(t),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      ))
                  .toList(),
            ),
          IconButton(
            icon: const Icon(Icons.local_offer_rounded, size: 14),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => _TagEditorDialog(note: note),
            ),
            tooltip: 'Edit Tags',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      color: color ?? cs.onSurfaceVariant,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
    );
  }
}

/// A toolbar icon that opens an anchored dropdown panel of related tools
/// (touch-sized [_DropdownToolButton]s in a [Wrap]) instead of spreading
/// every individual formatting action across the toolbar row — keeps the
/// pill from overflowing/needing horizontal scroll on narrow or touch
/// layouts while still surfacing every tool.
class _ToolGroupButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<Widget> tools;

  const _ToolGroupButton({
    required this.icon,
    required this.tooltip,
    required this.tools,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: () => _open(context),
      color: cs.onSurfaceVariant,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
    );
  }

  void _open(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset(0, box.size.height), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<void>(
      context: context,
      position: position,
      constraints: const BoxConstraints(maxWidth: 216),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          // enabled: false dims descendants via IconTheme.merge(opacity:
          // ~0.38) so Flutter can grey out disabled menu entries — reset it
          // here since these tiles are real (enabled) controls, not text.
          child: IconTheme.merge(
            data: const IconThemeData(opacity: 1.0),
            child: Wrap(children: tools),
          ),
        ),
      ],
    );
  }
}

/// A single tool tile inside a [_ToolGroupButton]'s dropdown panel. Sized to
/// a 44x44 touch target (vs. the 32x32 [_ToolbarButton]s used directly on
/// the toolbar row) and closes the dropdown itself on tap, since it lives
/// inside a `showMenu` item with its own gesture handling rather than using
/// PopupMenuItem's built-in single-value selection.
class _DropdownToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _DropdownToolButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed == null
            ? null
            : () {
                Navigator.of(context).pop();
                onPressed!();
              },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: cs.outlineVariant,
    );
  }
}

/// Add/create tags on a note. Writes tag *names* (matching the verified
/// `tag=["TAGADDED"]` wire format from Note.CRUD capture — the server
/// resolves/creates by name; composite `tag_id`s like "Name@uid" are a
/// read-side detail, not what Note.set expects).
class _TagEditorDialog extends ConsumerStatefulWidget {
  final Note note;
  const _TagEditorDialog({required this.note});

  @override
  ConsumerState<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends ConsumerState<_TagEditorDialog> {
  late Set<String> _selectedNames;
  final _newTagController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final tagNames = ref.read(tagNameMapProvider);
    _selectedNames = widget.note.tags.map((t) => tagNames[t] ?? t).toSet();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _addTypedTag() {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _selectedNames.add(name);
      _newTagController.clear();
    });
  }

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      final existingNames =
          (ref.read(tagsProvider).valueOrNull ?? []).map((t) => t.name).toSet();
      for (final name in _selectedNames) {
        if (!existingNames.contains(name)) await repo.createTag(name);
      }
      await repo.updateNote(
        noteId: widget.note.id,
        tagIds: _selectedNames.toList(),
      );
      syncAfterMutation(ref);
      if (mounted) {
        AppToast.success(context, 'Tags updated');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Update tags failed: $e');
      if (mounted) AppToast.error(context, 'Could not update tags.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];

    return AlertDialog(
      title: const Text('Edit Tags'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tags.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: tags
                      .map((t) => CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.name),
                            value: _selectedNames.contains(t.name),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selectedNames.add(t.name);
                              } else {
                                _selectedNames.remove(t.name);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _newTagController,
              decoration: InputDecoration(
                labelText: 'New tag',
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: _addTypedTag,
                ),
              ),
              onSubmitted: (_) => _addTypedTag(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _NoNoteSelected extends StatelessWidget {
  const _NoNoteSelected();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Select a note to start editing',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'or create a new note in your notebook',
              style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
