import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import '../../core/crypto/note_crypto.dart';
import '../../models/note.dart';
import '../../providers/notes_provider.dart';
import '../../providers/notebooks_provider.dart';
import '../../providers/api_provider.dart';
import '../../providers/tags_provider.dart';

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
    if (service == null) return;

    try {
      await service.updateNote(
        noteId: widget.note.id,
        title: _titleController.text,
        // Data-loss guard: only write body for plain notes. Rich/encrypted
        // content is never round-tripped through the plain-text editor.
        content: _isPlainEditable
            ? '<p>${_contentController.text.replaceAll('\n', '</p><p>')}</p>'
            : null,
      );
      if (mounted) {
        setState(() {
          _isDirty = false;
          _editing = false;
        });
      }
      ref.invalidate(notesProvider);
      ref.invalidate(selectedNoteProvider);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Gate encrypted notes behind a password prompt until unlocked.
    if (_isEncrypted && _decryptedHtml == null) {
      return Container(
        color: cs.surface,
        child: Column(
          children: [
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
          _EditorToolbar(
            note: widget.note,
            isDirty: _isDirty,
            editing: _editing,
            canEdit: _isPlainEditable,
            onSave: _saveNote,
            onToggleEdit: () => setState(() => _editing = !_editing),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          _EditorMeta(note: widget.note),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _editing && _isPlainEditable
                ? _buildPlainEditor(context, cs)
                : _buildReadView(context, cs),
          ),
        ],
      ),
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
          if (!_isPlainEditable && !_isEncrypted) ...[
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

class _EditorToolbar extends ConsumerWidget {
  final Note note;
  final bool isDirty;
  final bool editing;
  final bool canEdit;
  final VoidCallback onSave;
  final VoidCallback onToggleEdit;

  const _EditorToolbar({
    required this.note,
    required this.isDirty,
    required this.editing,
    required this.canEdit,
    required this.onSave,
    required this.onToggleEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (editing) ...[
            // Rich formatting controls are part of the future WebView editor;
            // disabled in the interim plain-text editor so they're not misleading.
            _ToolbarButton(
                icon: Icons.format_bold, tooltip: 'Bold (coming soon)'),
            _ToolbarButton(
                icon: Icons.format_italic, tooltip: 'Italic (coming soon)'),
            _ToolbarButton(
                icon: Icons.format_list_bulleted,
                tooltip: 'List (coming soon)'),
            const _ToolbarDivider(),
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
              } catch (_) {}
            },
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
            onPressed: () {},
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
