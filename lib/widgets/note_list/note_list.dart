import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/note.dart';
import '../../models/notebook.dart';
import '../../providers/app_mode_provider.dart'
    show repositoryProvider, appModeProvider, AppMode;
import '../../providers/note_color_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/notebooks_provider.dart';
import '../../providers/tags_provider.dart';
import '../common/app_toast.dart';

class NoteList extends ConsumerWidget {
  const NoteList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(notesProvider);
    final selectedId = ref.watch(selectedNoteIdProvider);
    final selectedNotebook = ref.watch(selectedNotebookProvider);

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          _NoteListHeader(
            title: selectedNotebook?.name ?? 'All Notes',
          ),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off_rounded,
                          size: 40, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text('Failed to load notes',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => ref.invalidate(notesProvider),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (_) {
                final notes = ref.watch(filteredNotesProvider);
                if (notes.isEmpty) {
                  return _EmptyState(
                      hasNotebook: selectedNotebook != null);
                }
                return ListView.separated(
                  itemCount: notes.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    return _NoteListItem(
                      note: note,
                      isSelected: note.id == selectedId,
                      onTap: () => ref
                          .read(selectedNoteIdProvider.notifier)
                          .state = note.id,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteListHeader extends ConsumerWidget {
  final String title;
  const _NoteListHeader({required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final count = ref.watch(filteredNotesProvider).length;
    final query = ref.watch(searchQueryProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _createNote(context, ref),
                tooltip: 'New Note',
                iconSize: 20,
                color: cs.primary,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search notes…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: TextStyle(fontSize: 13, color: cs.onSurface),
            onChanged: (v) =>
                ref.read(searchQueryProvider.notifier).state = v,
            controller: TextEditingController(text: query)
              ..selection = TextSelection(
                baseOffset: query.length,
                extentOffset: query.length,
              ),
          ),
        ],
      ),
    );
  }
}

class _NoteListItem extends ConsumerWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;

  const _NoteListItem({
    required this.note,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tagNames = ref.watch(tagNameMapProvider);
    final dateStr = _formatDate(note.updatedAt ?? note.createdAt);
    final noteColor = ref.watch(noteColorsProvider)[note.id];
    final noteColorLabel =
        noteColor == null ? null : ref.watch(colorLabelsProvider)[noteColor.toARGB32()];

    final resolvedTags = note.tags
        .map((id) => tagNames[id] ?? id)
        .take(3)
        .toList();

    return Material(
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: isSelected || noteColor != null
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: isSelected ? cs.primary : noteColor!,
                      width: isSelected ? 2 : 3,
                    ),
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.push_pin_rounded,
                          size: 12, color: cs.primary),
                    ),
                  if (note.isFavorite)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.star_rounded,
                          size: 12, color: Color(0xFFF59E0B)),
                    ),
                  if (note.isEncrypted)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock_rounded,
                          size: 12, color: cs.onSurfaceVariant),
                    ),
                  Expanded(
                    child: Text(
                      note.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    dateStr,
                    style:
                        TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  IconButton(
                    icon: Icon(
                      noteColor != null
                          ? Icons.label_rounded
                          : Icons.label_outline_rounded,
                      size: 15,
                    ),
                    tooltip: noteColorLabel ?? 'Set Color',
                    color: noteColor ?? cs.onSurfaceVariant,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 6),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showColorPicker(context, ref,
                        id: note.id, colorsProvider: noteColorsProvider),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 15),
                    tooltip: 'Delete Note',
                    color: cs.onSurfaceVariant,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.only(left: 6),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDeleteNote(context, ref, note),
                  ),
                ],
              ),
              if (note.displayExcerpt.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  note.displayExcerpt,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (resolvedTags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: resolvedTags
                      .map((tag) => _TagChip(tag: tag))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(dt);
    if (diff.inDays < 7) return DateFormat('EEE').format(dt);
    if (dt.year == now.year) return DateFormat('MMM d').format(dt);
    return DateFormat('MM/dd/yy').format(dt);
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          color: cs.onSecondaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  final bool hasNotebook;
  const _EmptyState({required this.hasNotebook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            hasNotebook ? 'No notes in this notebook' : 'No notes found',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _createNote(context, ref),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New Note'),
          ),
        ],
      ),
    );
  }
}

// ── Delete note (local mode only — NAS delete semantics aren't verified yet) ──

void _confirmDeleteNote(BuildContext context, WidgetRef ref, Note note) {
  final isLocal = ref.read(appModeProvider) == AppMode.local;
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Note?'),
      content: Text(
        isLocal
            ? 'Delete "${note.title}"? This cannot be undone.'
            : 'Move "${note.title}" to trash?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            final repo = ref.read(repositoryProvider);
            if (repo == null) return;
            try {
              await repo.deleteNote(note.id);
              if (ref.read(selectedNoteIdProvider) == note.id) {
                ref.read(selectedNoteIdProvider.notifier).state = null;
              }
              ref.invalidate(notesProvider);
              ref.invalidate(notebooksProvider);
              if (context.mounted) {
                AppToast.success(
                  context,
                  isLocal ? 'Note deleted' : 'Moved to trash',
                );
              }
            } catch (_) {
              if (context.mounted) {
                AppToast.error(context, 'Could not delete the note.');
              }
            }
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

// ── New note creation ────────────────────────────────────────────────────────

Future<void> _createNote(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  if (repo == null) return;

  var notebookId = ref.read(selectedNotebookIdProvider);
  if (notebookId == null) {
    final notebooks = ref.read(notebooksProvider).valueOrNull ?? [];
    if (notebooks.isEmpty) {
      AppToast.error(context, 'Create a notebook first.');
      return;
    }
    notebookId = await showDialog<String>(
      context: context,
      builder: (context) => _PickNotebookDialog(notebooks: notebooks),
    );
    if (notebookId == null) return; // cancelled
    if (!context.mounted) return;
  }

  // Note creation is a real round-trip in NAS mode (and noticeably slow even
  // locally) — show progress rather than leaving the "+" tap looking inert.
  final progress = AppToast.progress(context, 'Creating note…');

  try {
    final note = await repo.createNote(notebookId: notebookId, title: 'Untitled Note');
    ref.invalidate(notesProvider);
    ref.invalidate(notebooksProvider);
    ref.read(selectedNotebookIdProvider.notifier).state = notebookId;
    ref.read(selectedNoteIdProvider.notifier).state = note.id;
    progress.close();
  } catch (_) {
    progress.close();
    if (context.mounted) AppToast.error(context, 'Could not create the note.');
  }
}

class _PickNotebookDialog extends StatelessWidget {
  final List<Notebook> notebooks;
  const _PickNotebookDialog({required this.notebooks});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New note in…'),
      content: SizedBox(
        width: 320,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: notebooks.length,
          itemBuilder: (context, i) {
            final nb = notebooks[i];
            return ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(nb.name),
              onTap: () => Navigator.of(context).pop(nb.id),
            );
          },
        ),
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
