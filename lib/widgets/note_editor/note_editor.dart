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
  final _contentController = TextEditingController();
  final _richEditorKey = GlobalKey<RichHtmlEditorState>();
  bool _isDirty = false;
  bool _editing = false;

  // Encrypted notes: decrypted HTML once the user unlocks (read-only).
  String? _decryptedHtml;

  // Tags whose content is plain enough to round-trip through a plain-text editor
  // without losing formatting. Anything richer is read-only (see _isPlainEditable).
  static final _richTag = RegExp(
    r'<\s*(h[1-6]|table|thead|tbody|tr|td|th|ul|ol|li|img|span|b|i|u|s|hr|input'
    r'|sup|sub|a|strong|em|blockquote|code|pre|font)\b|style\s*=',
    caseSensitive: false,
  );

  bool get _isEncrypted =>
      widget.note.isEncrypted || NoteCrypto.isEncrypted(widget.note.content);

  /// HTML to display: decrypted body for encrypted notes, else the raw content.
  String get _displayHtml => _decryptedHtml ?? widget.note.content;

  /// Display HTML with NoteStation's checkbox `<input type="image">` markers
  /// (which point at an unreachable relative gif) swapped for plain glyphs.
  String get _renderHtml => _displayHtml
      .replaceAll(
          RegExp(r'<input[^>]*checkbox-checked[^>]*>', caseSensitive: false),
          '&#9745; ')
      .replaceAll(
          RegExp(r'<input[^>]*syno-notestation-editor-checkbox[^>]*>',
              caseSensitive: false),
          '&#9744; ');

  bool get _isPlainEditable =>
      !_isEncrypted && !_richTag.hasMatch(_displayHtml);

  /// Notes that aren't plain but use only the confirmed-preserved HTML
  /// vocabulary (see rich_html_schema.dart) get the real rich-text editor
  /// instead of the read-only fallback. Anything outside that vocabulary
  /// (links, real images, code blocks, ...) stays read-only, same as before
  /// this editor existed — fidelity-first, per docs/RICH-TEXT.md.
  bool get _isRichRoundTrippable =>
      !_isEncrypted &&
      !_isPlainEditable &&
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

  void _loadNote(Note note) {
    _titleController.text = note.title;
    _contentController.text =
        note.content.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    _isDirty = false;
    _editing = false;
    _decryptedHtml = null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
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
      // Data-loss guard: only write a body for notes editable in one of the
      // two safe editors. Encrypted/unconfirmed-schema notes never get a
      // content write here — they aren't reachable in an editing state.
      String? content;
      if (_isPlainEditable) {
        content = '<p>${_contentController.text.replaceAll('\n', '</p><p>')}</p>';
      } else if (_isRichRoundTrippable) {
        content = await _richEditorKey.currentState?.getContent();
      }

      await service.updateNote(
        noteId: widget.note.id,
        title: _titleController.text,
        content: content,
      );
      if (mounted) {
        setState(() {
          _isDirty = false;
          _editing = false;
        });
        AppToast.success(context, 'Note saved');
      }
      ref.invalidate(notesProvider);
      ref.invalidate(selectedNoteProvider);
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not save the note.');
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
            canEdit: _isPlainEditable || _isRichRoundTrippable,
            isRichEditing: _editing && _isRichRoundTrippable,
            richEditorKey: _richEditorKey,
            onSave: _saveNote,
            onToggleEdit: () => setState(() => _editing = !_editing),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          _EditorMeta(note: widget.note),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _editing && _isPlainEditable
                ? _buildPlainEditor(context, cs)
                : _editing && _isRichRoundTrippable
                    ? _buildRichEditor(context, cs)
                    : _buildReadView(context, cs),
          ),
        ],
      ),
    );
  }

  Widget _buildRichEditor(BuildContext context, ColorScheme cs) {
    return RichHtmlEditor(
      key: _richEditorKey,
      initialHtml: _displayHtml,
      darkMode: Theme.of(context).brightness == Brightness.dark,
      onDirty: () {
        if (!_isDirty) setState(() => _isDirty = true);
      },
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
          ),
          const SizedBox(height: 16),
          if (_displayHtml.trim().isEmpty)
            Text('This note is empty.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14))
          else
            // ExcludeSemantics works around a Flutter framework assertion
            // (!semantics.parentDataDirty) triggered by the HTML renderer's
            // inline WidgetSpans (checkbox images, <hr>, tables) on Flutter 3.41.
            ExcludeSemantics(
              child: HtmlWidget(
                _renderHtml,
                textStyle: TextStyle(
                    fontSize: 15, color: cs.onSurface, height: 1.6),
              ),
            ),
          if (!_isPlainEditable && !_isRichRoundTrippable && !_isEncrypted) ...[
            const SizedBox(height: 24),
            _RichReadOnlyBanner(cs: cs),
          ],
        ],
      ),
    );
  }

  Widget _buildPlainEditor(BuildContext context, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
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
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _contentController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style:
                  TextStyle(fontSize: 15, color: cs.onSurface, height: 1.7),
              decoration: InputDecoration(
                hintText: 'Start writing…',
                hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => setState(() => _isDirty = true),
            ),
          ),
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
          Icon(Icons.info_outline_rounded, size: 16, color: cs.onSurfaceVariant),
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
      ref.invalidate(notesProvider);
      ref.invalidate(notebooksProvider);
      // NAS mode returns a new note id (the old one was trashed) — follow it.
      ref.read(selectedNoteIdProvider.notifier).state = encrypted.id;
      ref.invalidate(selectedNoteProvider);
      if (mounted) {
        AppToast.success(context, 'Note encrypted');
        Navigator.of(context).pop();
      }
    } catch (_) {
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
                    _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
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

class _EditorToolbar extends ConsumerWidget {
  final Note note;
  final bool isDirty;
  final bool editing;
  final bool canEdit;
  final bool isRichEditing;
  final GlobalKey<RichHtmlEditorState> richEditorKey;
  final VoidCallback onSave;
  final VoidCallback onToggleEdit;

  const _EditorToolbar({
    required this.note,
    required this.isDirty,
    required this.editing,
    required this.canEdit,
    required this.isRichEditing,
    required this.richEditorKey,
    required this.onSave,
    required this.onToggleEdit,
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
    final noteColorLabel =
        noteColor == null ? null : ref.watch(colorLabelsProvider)[noteColor.toARGB32()];
    return Container(
      height: 44,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (editing && isRichEditing) ...[
            _ToolbarButton(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                onPressed: () => _rich?.bold()),
            _ToolbarButton(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                onPressed: () => _rich?.italic()),
            _ToolbarButton(
                icon: Icons.format_underline,
                tooltip: 'Underline',
                onPressed: () => _rich?.underline()),
            _ToolbarButton(
                icon: Icons.strikethrough_s_rounded,
                tooltip: 'Strikethrough',
                onPressed: () => _rich?.strikethrough()),
            const _ToolbarDivider(),
            _ToolbarButton(
                icon: Icons.superscript_rounded,
                tooltip: 'Superscript',
                onPressed: () => _rich?.superscript()),
            _ToolbarButton(
                icon: Icons.subscript_rounded,
                tooltip: 'Subscript',
                onPressed: () => _rich?.subscript()),
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
            _ToolbarButton(
                icon: Icons.format_list_bulleted,
                tooltip: 'Bullet list',
                onPressed: () => _rich?.unorderedList()),
            _ToolbarButton(
                icon: Icons.format_list_numbered_rounded,
                tooltip: 'Numbered list',
                onPressed: () => _rich?.orderedList()),
            const _ToolbarDivider(),
            _ToolbarButton(
                icon: Icons.format_color_text_rounded,
                tooltip: 'Text color',
                onPressed: () =>
                    _pickAndApply(context, (c) => _rich?.fontColor(c))),
            _ToolbarButton(
                icon: Icons.format_color_fill_rounded,
                tooltip: 'Highlight',
                onPressed: () =>
                    _pickAndApply(context, (c) => _rich?.highlight(c))),
            const _ToolbarDivider(),
            _ToolbarButton(
                icon: Icons.check_box_outlined,
                tooltip: 'Checkbox',
                onPressed: () => _rich?.insertCheckbox()),
            _ToolbarButton(
                icon: Icons.table_chart_outlined,
                tooltip: 'Table',
                onPressed: () => _rich?.insertTable()),
            _ToolbarButton(
                icon: Icons.horizontal_rule_rounded,
                tooltip: 'Divider',
                onPressed: () => _rich?.insertDivider()),
          ] else if (editing) ...[
            Text('Plain-text editing',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
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
          if (canEdit)
            _ToolbarButton(
              icon: editing ? Icons.visibility_rounded : Icons.edit_rounded,
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
                ref.invalidate(selectedNoteProvider);
                ref.invalidate(notesProvider);
              } catch (_) {
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
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
          Icon(Icons.access_time_rounded,
              size: 13, color: cs.onSurfaceVariant),
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
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
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
    _selectedNames =
        widget.note.tags.map((t) => tagNames[t] ?? t).toSet();
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
      ref.invalidate(tagsProvider);
      ref.invalidate(notesProvider);
      ref.invalidate(selectedNoteProvider);
      if (mounted) {
        AppToast.success(context, 'Tags updated');
        Navigator.of(context).pop();
      }
    } catch (_) {
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
            Icon(Icons.edit_note_rounded,
                size: 64, color: cs.onSurfaceVariant),
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
