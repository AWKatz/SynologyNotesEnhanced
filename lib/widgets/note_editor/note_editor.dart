import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import '../../core/crypto/note_crypto.dart';
import '../../core/rich_html/rich_html_schema.dart';
import '../../models/note.dart';
import '../../models/note_acl.dart';
import '../../models/note_version.dart';
import '../../providers/app_mode_provider.dart'
    show repositoryProvider, mobileTabIndexProvider;
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

  // Encrypted notes: decrypted HTML once the user unlocks, plus the password
  // that unlocked it (needed to re-encrypt on save — see _saveNote).
  String? _decryptedHtml;
  String? _unlockPassword;

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
  /// display URL (see [_resolveImages]). The checked glyph is tinted with
  /// the user's chosen accent color, matching the checked-checkbox fill the
  /// WebView rich editor applies via its own --accent (see
  /// RichHtmlEditor.onLoadStop / editor.js's setAccentColor) — this
  /// read-only glyph rendering path doesn't share that CSS, so without this
  /// it would render in the plain body text color instead.
  String get _renderHtml {
    final accentHex =
        '#${Theme.of(context).colorScheme.primary.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return _resolveImages(_displayHtml)
        .replaceAll(
            RegExp(r'<input[^>]*checkbox-checked[^>]*>', caseSensitive: false),
            '<span style="color:$accentHex">&#9745;</span> ')
        .replaceAll(
            RegExp(r'<input[^>]*syno-notestation-editor-checkbox[^>]*>',
                caseSensitive: false),
            '&#9744; ');
  }

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

    final refsInHtml =
        RegExp(r'<img\b[^>]*\bref="([^"]*)"', caseSensitive: false)
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
    final claimedKeys =
        refsInHtml.where((r) => widget.note.attachment.containsKey(r)).toSet();
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
    final refsInHtml =
        RegExp(r'<img\b[^>]*\bref="([^"]*)"', caseSensitive: false)
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
      final meta = key == null
          ? null
          : widget.note.attachment[key] as Map<String, dynamic>?;
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
  ///
  /// Encrypted notes gate on whether they're *currently* unlocked
  /// (_decryptedHtml set), not just on _isEncrypted — the note's original
  /// encrypted flag never changes, but once the user has entered the
  /// password this session there's decrypted HTML to edit. _saveNote
  /// re-encrypts with _unlockPassword before writing back.
  bool get _isEditable =>
      (!_isEncrypted || _decryptedHtml != null) &&
      RichHtmlSchema.isRoundTrippable(_displayHtml);

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

  /// Mirrors [_editing] into [noteEditingProvider] so sibling widgets outside
  /// this editor (the "new note" FAB, positioned over it in a Stack) know
  /// when rich-edit mode is active without needing access to this State.
  void _setEditing(bool value) {
    _editing = value;
    ref.read(noteEditingProvider.notifier).state = value;
  }

  void _loadNote(Note note) {
    _titleController.text = note.title;
    _isDirty = false;
    _setEditing(false);
    _decryptedHtml = null;
    _unlockPassword = null;
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
      setState(() => _setEditing(false));
      return;
    }
    if (!RegExp(r'<img\b[^>]*\bref=').hasMatch(_displayHtml)) {
      setState(() => _setEditing(true));
      return;
    }
    setState(() => _preparingEditor = true);
    final resolved = await _resolveImagesForEditor(_displayHtml);
    if (!mounted) return;
    setState(() {
      _richEditorHtml = resolved;
      _setEditing(true);
      _preparingEditor = false;
    });
  }

  /// Save-then-leave, mirroring Samsung Notes' back arrow — a no-op save
  /// call when nothing's dirty is harmless (_saveNote early-returns).
  /// Clearing the selection is enough to leave the editor on every layout
  /// (three/two-panel editors show "Select a note" again); mobile also
  /// needs its tab flipped back to Notes since that layout has no note
  /// list visible alongside the editor to fall back to.
  void _goBack() {
    if (_editing && _isDirty) _saveNote();
    ref.read(selectedNoteIdProvider.notifier).state = null;
    ref.read(mobileTabIndexProvider.notifier).state = 1;
  }

  @override
  void deactivate() {
    // ref is no longer usable once dispose() begins (Riverpod asserts on
    // it — confirmed via a real "Cannot use ref after the widget was
    // disposed" crash here), so this cleanup has to happen in deactivate()
    // instead, while the element is still attached.
    ref.read(noteEditingProvider.notifier).state = false;
    super.deactivate();
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
      // mounted. Unconfirmed-schema notes never get a content write here —
      // they aren't reachable in an editing state. Encrypted notes ARE
      // reachable once unlocked; getContent() returns plaintext HTML (the
      // WebView was loaded with _decryptedHtml), so it's re-encrypted with
      // _unlockPassword below before anything is sent over the wire —
      // otherwise a save would silently turn the note back into plaintext
      // server-side.
      String? content;
      if (_isEditable) {
        content = await _richEditorKey.currentState?.getContent();
        if (content != null && _isEncrypted) {
          content = NoteCrypto.encrypt(content, _unlockPassword!);
        }
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
          _setEditing(false);
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
    if (_isEncrypted) {
      // uploadNoteAttachment's multipart Note.set correlates the upload to a
      // plaintext `<img ref="...">` tag inside `content` — never verified
      // against an encrypted note (content would be the ciphertext blob, not
      // HTML), so this stays unsupported rather than risk a malformed write.
      AppToast.error(
          context, 'Inserting images into an encrypted note isn\'t supported.');
      return;
    }
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
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
                onUnlocked: (html, password) => setState(() {
                  _decryptedHtml = html;
                  _unlockPassword = password;
                }),
              ),
            ),
          ],
        ),
      );
    }

    final isRichEditing = _editing && _isEditable;

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          colorStrip,
          _EditorMeta(
            note: widget.note,
            isDirty: _isDirty,
            editing: _editing,
            canEdit: _isEditable,
            preparingEdit: _preparingEditor,
            onSave: _saveNote,
            onToggleEdit: _toggleEdit,
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: isRichEditing
                ? _buildRichEditor(context, cs)
                : _buildReadView(context, cs),
          ),
          // Anchored above the keyboard (see _EditorToolbar's doc comment) —
          // only relevant, so only shown, while actively rich-editing.
          if (isRichEditing)
            _EditorToolbar(
              richEditorKey: _richEditorKey,
              onInsertImage: _insertImage,
            ),
        ],
      ),
    );
  }

  /// Leads the title row on both the rich-edit and read views — pressing it
  /// saves (if dirty) and leaves the editor. See [_goBack].
  Widget _titleBackButton(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        tooltip: 'Save and go back',
        onPressed: _goBack,
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(4),
        color: cs.onSurfaceVariant,
      ),
    );
  }

  Widget _buildRichEditor(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 32, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _titleBackButton(cs),
              Expanded(
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
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(() => _isDirty = true),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RichHtmlEditor(
            key: _richEditorKey,
            initialHtml: _richEditorHtml ?? _resolveImages(_displayHtml),
            darkMode: Theme.of(context).brightness == Brightness.dark,
            accentColor: Theme.of(context).colorScheme.primary,
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            onDirty: () {
              if (!_isDirty) setState(() => _isDirty = true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReadView(BuildContext context, ColorScheme cs) {
    // Top padding matches _buildRichEditor's title row exactly (8, not the
    // old 24) so toggling edit mode doesn't visibly shift the title/body
    // text vertically — both then add the same 16px gap before body
    // content (the SizedBox below vs. editor.css's #editor padding-top).
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _titleBackButton(cs),
              Expanded(
                child: Text(
                  widget.note.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                ),
              ),
            ],
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
  final void Function(String html, String password) onUnlocked;
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
      if (mounted) widget.onUnlocked(html, password);
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
  State<_TableSizePickerDialog> createState() => _TableSizePickerDialogState();
}

class _TableSizePickerDialogState extends State<_TableSizePickerDialog> {
  static const int _maxRows = 6;
  static const int _maxCols = 8;
  static const double _cellSize = 28;
  static const double _cellGap = 4;

  int _hoverRows = 1;
  int _hoverCols = 1;

  void _updateFromLocalPosition(Offset local) {
    final col = (local.dx / (_cellSize + _cellGap)).ceil().clamp(1, _maxCols);
    final row = (local.dy / (_cellSize + _cellGap)).ceil().clamp(1, _maxRows);
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

/// Rich-text formatting toolbar. Lives at the bottom of the editor Column
/// (below the Expanded content), so with the ancestor Scaffold's default
/// resizeToAvoidBottomInset it naturally lands right above the on-screen
/// keyboard — the same anchored-above-keyboard placement Samsung Notes uses
/// — rather than floating at the top of the panel like the old pill toolbar.
/// Only rendered while actively rich-editing; the non-formatting actions
/// (save/favorite/tag/encrypt/move) live in _EditorMeta's overflow menu.
class _EditorToolbar extends ConsumerWidget {
  final GlobalKey<RichHtmlEditorState> richEditorKey;
  final Future<void> Function() onInsertImage;

  const _EditorToolbar({
    required this.richEditorKey,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        onPressed: () =>
                            _pickAndApply(context, (c) => _rich?.fontColor(c))),
                    _DropdownToolButton(
                        icon: Icons.format_color_fill_rounded,
                        tooltip: 'Highlight',
                        onPressed: () =>
                            _pickAndApply(context, (c) => _rich?.highlight(c))),
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
                  onSelected: (level) =>
                      level == 0 ? _rich?.paragraph() : _rich?.heading(level),
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
                          builder: (context) => const _TableSizePickerDialog(),
                        );
                        if (size != null) {
                          _rich?.insertTable(rows: size.$1, cols: size.$2);
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
                    PopupMenuItem(value: 'insert', child: Text('Insert table')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'row_above', child: Text('Insert row above')),
                    PopupMenuItem(
                        value: 'row_below', child: Text('Insert row below')),
                    PopupMenuItem(
                        value: 'col_left', child: Text('Insert column left')),
                    PopupMenuItem(
                        value: 'col_right', child: Text('Insert column right')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'delete_row', child: Text('Delete row')),
                    PopupMenuItem(
                        value: 'delete_col', child: Text('Delete column')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'delete_table', child: Text('Delete table')),
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
        ),
      ),
    );
  }
}

class _EditorMeta extends ConsumerWidget {
  final Note note;
  final bool isDirty;
  final bool editing;
  final bool canEdit;
  final bool preparingEdit;
  final VoidCallback? onSave;
  final VoidCallback? onToggleEdit;

  const _EditorMeta({
    required this.note,
    this.isDirty = false,
    this.editing = false,
    this.canEdit = false,
    this.preparingEdit = false,
    this.onSave,
    this.onToggleEdit,
  });

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
    final noteColor = ref.watch(noteColorsProvider)[note.id];
    final noteColorLabel = noteColor == null
        ? null
        : ref.watch(colorLabelsProvider)[noteColor.toARGB32()];

    final resolvedTags = note.tags.map((id) => tagNames[id] ?? id).toList();

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        children: [
          // Notebook/date/tags share this Expanded so they truncate instead
          // of forcing a RenderFlex overflow at narrow (phone) widths — the
          // trailing icon cluster after it (tag/edit/overflow) is the set of
          // actionable controls and must stay fully visible, never squeezed.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => _MoveNoteDialog(note: note),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 2, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_rounded,
                              size: 13,
                              color: cs.primary.withValues(alpha: 0.7)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              notebook?.name ?? 'Unknown Notebook',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.unfold_more_rounded,
                              size: 12, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time_rounded,
                    size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    updatedAt != null
                        ? DateFormat('MMM d, yyyy · HH:mm').format(updatedAt)
                        : 'Unknown date',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
                if (resolvedTags.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Flexible(
                    child: Wrap(
                      spacing: 4,
                      children: resolvedTags
                          .map((t) => Chip(
                                label: Text(t),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Transient — shown briefly while entering edit mode on a note
          // with images (see _toggleEdit's image-resolution branch). Kept
          // outside the More menu since it's a loading state, not an option.
          if (canEdit && preparingEdit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          // This slot always holds the one primary action for the current
          // mode — Edit while just viewing, then Save/Done while editing
          // (Save once something's actually changed, Done otherwise, so
          // tapping it always does something sensible instead of Save
          // silently no-op'ing on a clean note) — anchored at the far right
          // with only the More menu beside it. Everything else (tags,
          // favorite, color, encrypt, move) lives in that menu instead of
          // competing for space in this row.
          if (editing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: OutlinedButton.icon(
                onPressed: isDirty ? onSave : onToggleEdit,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text(isDirty ? 'Save' : 'Done'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else if (canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: OutlinedButton.icon(
                onPressed: onToggleEdit,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert_rounded,
                size: 16, color: cs.onSurfaceVariant),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            itemBuilder: (context) => [
              // Edit/Save/Done all live in the dedicated primary-action slot
              // this menu sits beside — nothing to duplicate here for either.
              const PopupMenuItem(
                value: 'tags',
                child: ListTile(
                  leading: Icon(Icons.local_offer_rounded),
                  title: Text('Edit Tags'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'favorite',
                child: ListTile(
                  leading: Icon(note.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_border_rounded),
                  title: Text(note.isFavorite ? 'Unfavorite' : 'Favourite'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'color',
                child: ListTile(
                  leading: Icon(noteColor != null
                      ? Icons.label_rounded
                      : Icons.label_outline_rounded),
                  title: Text(noteColorLabel ?? 'Set Color'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!note.isEncrypted)
                const PopupMenuItem(
                  value: 'encrypt',
                  child: ListTile(
                    leading: Icon(Icons.lock_outline_rounded),
                    title: Text('Encrypt Note'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'move',
                child: ListTile(
                  leading: Icon(Icons.drive_file_move_rounded),
                  title: Text('Move to Notebook'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              // NAS-only (Permission/Share.Priv/Shard.Link APIs), and not
              // offered for encrypted notes — sharing ciphertext content has
              // never been captured, so this stays out of scope rather than
              // guess at the interaction.
              if (ref.watch(noteStationServiceProvider) != null &&
                  !note.isEncrypted)
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_rounded),
                    title: Text('Share'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              // NAS-only (Note.Version list/restore). Not offered for
              // encrypted notes — a past revision's content comes back as a
              // ciphertext blob with no verified way to preview/decrypt it
              // here, so this stays out of scope rather than guess.
              if (ref.watch(noteStationServiceProvider) != null &&
                  !note.isEncrypted)
                const PopupMenuItem(
                  value: 'history',
                  child: ListTile(
                    leading: Icon(Icons.history_rounded),
                    title: Text('Version History'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'tags':
                  showDialog<void>(
                    context: context,
                    builder: (context) => _TagEditorDialog(note: note),
                  );
                case 'favorite':
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
                case 'color':
                  showColorPicker(context, ref,
                      id: note.id, colorsProvider: noteColorsProvider);
                case 'encrypt':
                  showDialog<void>(
                    context: context,
                    builder: (context) => _EncryptNoteDialog(note: note),
                  );
                case 'move':
                  showDialog<void>(
                    context: context,
                    builder: (context) => _MoveNoteDialog(note: note),
                  );
                case 'share':
                  showDialog<void>(
                    context: context,
                    builder: (context) => _ShareNoteDialog(note: note),
                  );
                case 'history':
                  showDialog<void>(
                    context: context,
                    builder: (context) => _VersionHistoryDialog(note: note),
                  );
              }
            },
          ),
        ],
      ),
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

class _MoveNoteDialog extends ConsumerStatefulWidget {
  final Note note;
  const _MoveNoteDialog({required this.note});

  @override
  ConsumerState<_MoveNoteDialog> createState() => _MoveNoteDialogState();
}

class _MoveNoteDialogState extends ConsumerState<_MoveNoteDialog> {
  late String? _selectedNotebookId = widget.note.notebookId;
  bool _busy = false;

  Future<void> _move() async {
    final target = _selectedNotebookId;
    if (target == null || target == widget.note.notebookId) {
      Navigator.of(context).pop();
      return;
    }
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.updateNote(noteId: widget.note.id, notebookId: target);
      syncAfterMutation(ref);
      if (mounted) {
        AppToast.success(context, 'Note moved');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Move note failed: $e');
      if (mounted) AppToast.error(context, 'Could not move note.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];

    return AlertDialog(
      title: const Text('Move to Notebook'),
      content: SizedBox(
        width: 320,
        child: notebooks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No notebooks available.'),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: notebooks
                      .map((nb) => RadioListTile<String>(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(nb.name),
                            value: nb.id,
                            groupValue: _selectedNotebookId,
                            onChanged: _busy
                                ? null
                                : (v) =>
                                    setState(() => _selectedNotebookId = v),
                          ))
                      .toList(),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _selectedNotebookId == widget.note.notebookId
              ? null
              : _move,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Move'),
        ),
      ],
    );
  }
}

// ── Share dialog ─────────────────────────────────────────────────────────────
//
// Built from what's captured across `.docs/reference/Note Sharing and
// Permissions*.har`, `.docs/reference/Share RW*.har`, and `.docs/reference/
// Revoke Share*.har`: enabling sharing + a public link (create/revoke),
// sharing with a DSM group OR an individual user, a read-only/read-write
// perm choice (rw directly verified on a user share; inferred by symmetry
// for group/public — see NoteStationService.setPublicPermission's doc
// comment), and removing a single USER's share (verified). Removing a
// single GROUP's share is ALSO offered here now but is UNVERIFIED — no
// capture of that specific call exists; it's built by symmetry with the
// user-remove call (see NoteStationService.deleteGroupPermission's doc
// comment) per Aaron's go-ahead (2026-07-31) to ship the guess and
// re-capture/fix if it doesn't actually work. Still not offered: disabling
// sharing outright (every Permission.set call captured — including both
// revoke flows — sent enabled:true; enabled:false has never been sent).
class _ShareNoteDialog extends ConsumerStatefulWidget {
  final Note note;
  const _ShareNoteDialog({required this.note});

  @override
  ConsumerState<_ShareNoteDialog> createState() => _ShareNoteDialogState();
}

class _ShareNoteDialogState extends ConsumerState<_ShareNoteDialog> {
  final _searchController = TextEditingController();
  bool _busy = false;
  String? _publicLink;
  String _newSharePerm = 'ro';
  List<({String name, String type})> _searchResults = [];

  @override
  void initState() {
    super.initState();
    if (widget.note.acl.publicPerm != null) _loadPublicLink();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPublicLink() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      final url = await repo.getPublicShareLink(widget.note.id);
      if (mounted) setState(() => _publicLink = url);
    } catch (e) {
      debugPrint('Get public share link failed: $e');
    }
  }

  Future<void> _createPublicLink() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.setSharingEnabled(widget.note.id, true);
      await repo.setPublicPermission(widget.note.id, _newSharePerm);
      await _loadPublicLink();
      syncAfterMutation(ref);
    } catch (e) {
      debugPrint('Create public link failed: $e');
      if (mounted) AppToast.error(context, 'Could not create the public link.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokePublicLink() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.deletePublicPermission(widget.note.id);
      if (mounted) setState(() => _publicLink = null);
      syncAfterMutation(ref);
    } catch (e) {
      debugPrint('Revoke public link failed: $e');
      if (mounted) AppToast.error(context, 'Could not revoke the public link.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search(String query) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null || query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    try {
      final results = await repo.searchSharePriv(query.trim());
      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      debugPrint('Share search failed: $e');
    }
  }

  Future<void> _shareWithGroup(String groupName) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.setSharingEnabled(widget.note.id, true);
      await repo.setGroupPermission(
          noteId: widget.note.id, groupName: groupName, perm: _newSharePerm);
      _searchController.clear();
      if (mounted) setState(() => _searchResults = []);
      syncAfterMutation(ref);
      if (mounted) AppToast.success(context, 'Shared with $groupName');
    } catch (e) {
      debugPrint('Share with group failed: $e');
      if (mounted) AppToast.error(context, 'Could not share with $groupName.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareWithUser(String username) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.setSharingEnabled(widget.note.id, true);
      await repo.setUserPermission(
          noteId: widget.note.id, username: username, perm: _newSharePerm);
      _searchController.clear();
      if (mounted) setState(() => _searchResults = []);
      syncAfterMutation(ref);
      if (mounted) AppToast.success(context, 'Shared with $username');
    } catch (e) {
      debugPrint('Share with user failed: $e');
      if (mounted) AppToast.error(context, 'Could not share with $username.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeUserShare(NoteUserShare share) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.deleteUserPermission(
          noteId: widget.note.id, username: share.name, uid: share.uid);
      syncAfterMutation(ref);
      if (mounted) AppToast.success(context, 'Removed ${share.name}');
    } catch (e) {
      debugPrint('Remove user share failed: $e');
      if (mounted) AppToast.error(context, 'Could not remove ${share.name}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // UNVERIFIED (see NoteStationService.deleteGroupPermission's doc comment)
  // — enabled per Aaron's go-ahead to try it and recapture if it doesn't
  // actually revoke the share.
  Future<void> _removeGroupShare(NoteGroupShare share) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.deleteGroupPermission(
          noteId: widget.note.id, groupName: share.name, gid: share.groupId);
      syncAfterMutation(ref);
      if (mounted) AppToast.success(context, 'Removed ${share.name}');
    } catch (e) {
      debugPrint('Remove group share failed: $e');
      if (mounted) AppToast.error(context, 'Could not remove ${share.name}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _permSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'ro', label: Text('Read only')),
        ButtonSegment(value: 'rw', label: Text('Read-write')),
      ],
      selected: {_newSharePerm},
      onSelectionChanged: _busy
          ? null
          : (s) => setState(() => _newSharePerm = s.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Re-read the freshest note (acl may have just changed) rather than the
    // possibly-stale widget.note captured when the dialog opened.
    final note = ref.watch(selectedNoteProvider).valueOrNull ?? widget.note;

    return AlertDialog(
      title: const Text('Share Note'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Public link', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              if (note.acl.publicPerm != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _publicLink ?? 'Loading…',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Copy link',
                      onPressed: _publicLink == null
                          ? null
                          : () {
                              Clipboard.setData(
                                  ClipboardData(text: _publicLink!));
                              AppToast.success(context, 'Link copied');
                            },
                    ),
                  ],
                ),
                Text('Permission: ${note.acl.publicPerm}',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                TextButton.icon(
                  onPressed: _busy ? null : _revokePublicLink,
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Revoke public link'),
                ),
              ] else ...[
                _permSelector(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _createPublicLink,
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('Create public link'),
                ),
              ],
              const SizedBox(height: 16),
              Text('Share with a user or group',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              _permSelector(),
              const SizedBox(height: 8),
              TextField(
                controller: _searchController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search users or groups…',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
                onChanged: _search,
              ),
              if (_searchResults.isNotEmpty)
                ...(_searchResults.map((r) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          r.type == 'group'
                              ? Icons.group_rounded
                              : Icons.person_rounded,
                          size: 18),
                      title: Text(r.name),
                      onTap: _busy
                          ? null
                          : () => r.type == 'group'
                              ? _shareWithGroup(r.name)
                              : _shareWithUser(r.name),
                    ))),
              if (note.acl.groups.isNotEmpty || note.acl.users.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Already shared with',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final g in note.acl.groups)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.group_rounded, size: 18),
                    title: Text(g.name),
                    subtitle: Text(g.perm),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Remove',
                      onPressed: _busy ? null : () => _removeGroupShare(g),
                    ),
                  ),
                for (final u in note.acl.users)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_rounded, size: 18),
                    title: Text(u.name),
                    subtitle: Text(u.perm),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Remove',
                      onPressed:
                          _busy ? null : () => _removeUserShare(u),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ── Version history dialog ───────────────────────────────────────────────────
//
// VERIFIED (`.docs/reference/Version restore*.har`): the list's lowest `id`
// is the CURRENT content (its `version`/`mtime` matched a Note.get taken
// moments earlier in the capture) and id increases going further back in
// time — the reverse of what "id" might suggest. Restoring calls
// Note.Version.restore(ver: <that revision's version sha>) directly; there's
// no verified preview step (the capture's own Note.get(ver:) before
// restoring appears to just be how the stock client happened to render a
// diff/preview, not a required step), so this restores immediately behind a
// confirmation dialog instead of adding an unverified preview UI.
class _VersionHistoryDialog extends ConsumerStatefulWidget {
  final Note note;
  const _VersionHistoryDialog({required this.note});

  @override
  ConsumerState<_VersionHistoryDialog> createState() =>
      _VersionHistoryDialogState();
}

class _VersionHistoryDialogState extends ConsumerState<_VersionHistoryDialog> {
  List<NoteVersion>? _versions;
  bool _loading = true;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      final versions = await repo.listNoteVersions(widget.note.id);
      // Lowest id = current/newest, ascending id = further back in time.
      versions.sort((a, b) => a.id.compareTo(b.id));
      if (mounted) {
        setState(() {
          _versions = versions;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('List note versions failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmRestore(NoteVersion v) async {
    final when = v.mtime != null
        ? DateFormat.yMMMd().add_jm().format(v.mtime!)
        : 'this revision';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this version?'),
        content: Text(
          'This replaces the note\'s current content with the version from '
          '$when. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _restoring = true);
    try {
      await repo.restoreNoteVersion(noteId: widget.note.id, ver: v.ver);
      syncAfterMutation(ref);
      if (mounted) {
        AppToast.success(context, 'Note restored');
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Restore note version failed: $e');
      if (mounted) AppToast.error(context, 'Could not restore this version.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Version History'),
      content: SizedBox(
        width: 380,
        height: 320,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : (_versions == null || _versions!.isEmpty)
                ? Center(
                    child: Text('No earlier versions',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  )
                : ListView.builder(
                    itemCount: _versions!.length,
                    itemBuilder: (context, i) {
                      final v = _versions![i];
                      final isCurrent = i == 0;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.radio_button_checked_rounded
                              : Icons.history_rounded,
                          size: 18,
                        ),
                        title: Text(v.mtime != null
                            ? DateFormat.yMMMd().add_jm().format(v.mtime!)
                            : 'Revision ${v.id}'),
                        subtitle: Text(v.author),
                        trailing: isCurrent
                            ? Text('Current',
                                style: TextStyle(
                                    fontSize: 11, color: cs.onSurfaceVariant))
                            : TextButton(
                                onPressed: _restoring
                                    ? null
                                    : () => _confirmRestore(v),
                                child: const Text('Restore'),
                              ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
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
