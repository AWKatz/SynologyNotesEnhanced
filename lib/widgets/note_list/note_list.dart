import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';
import '../../models/note.dart';
import '../../models/notebook.dart';
import '../../models/smart_notebook.dart';
import '../../models/tag.dart';
import '../../providers/app_mode_provider.dart'
    show repositoryProvider, appModeProvider, AppMode, mobileTabIndexProvider;
import '../../providers/folder_strip_provider.dart';
import '../../providers/note_color_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/notebooks_provider.dart';
import '../../providers/smart_notebooks_provider.dart';
import '../../providers/tags_provider.dart';
import '../common/app_toast.dart';

class NoteList extends ConsumerWidget {
  /// Opens the sidebar drawer when set — only supplied by _TwoPanelLayout
  /// (the drawer-based tablet layout), which has no AppBar of its own to
  /// host a hamburger button; the icon lives in the header row instead so
  /// it doesn't push "All Notes" down with a whole extra bar just for it.
  final VoidCallback? onMenuPressed;

  const NoteList({super.key, this.onMenuPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notesAsync = ref.watch(notesProvider);
    final selectedId = ref.watch(selectedNoteIdProvider);
    final selectedNotebook = ref.watch(selectedNotebookProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final selectedSmart = ref.watch(selectedSmartNotebookProvider);
    final filter = ref.watch(noteFilterProvider);
    // The folder strip is a quick-access shortcut into a notebook/tag/smart
    // notebook — only useful from the unscoped "All Notes" root, same as the
    // reference screenshots' own Folders hub. Once a notebook, tag, smart
    // notebook, or filter view is active, the grid below is already scoped,
    // so the strip would be redundant.
    final showFolderStrip = filter == null &&
        selectedNotebook == null &&
        selectedTag == null &&
        selectedSmart == null;

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          _NoteListHeader(onMenuPressed: onMenuPressed),
          if (showFolderStrip) const _FolderStrip(),
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
                  return _EmptyState(filter: filter);
                }
                return _NoteGrid(notes: notes, selectedId: selectedId);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "New note" FAB — lives over the editor panel (not the note list) so it
/// never overlaps the note grid it would otherwise float on top of.
class NewNoteFab extends ConsumerWidget {
  const NewNoteFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      onPressed: () => _createNote(context, ref),
      tooltip: 'New Note',
      child: const Icon(Icons.edit_rounded),
    );
  }
}

// ── Header: title, count, search, sort ───────────────────────────────────────

class _NoteListHeader extends ConsumerWidget {
  final VoidCallback? onMenuPressed;

  const _NoteListHeader({this.onMenuPressed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final count = ref.watch(filteredNotesProvider).length;
    final query = ref.watch(searchQueryProvider);
    final selectedNotebook = ref.watch(selectedNotebookProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final selectedSmart = ref.watch(selectedSmartNotebookProvider);
    final filter = ref.watch(noteFilterProvider);
    final (sortField, ascending) = ref.watch(noteSortProvider);

    final title = switch (filter) {
      NoteFilter.favorites => 'Favorites',
      NoteFilter.locked => 'Locked Notes',
      NoteFilter.shared => 'Shared Notes',
      NoteFilter.trash => 'Trash',
      null => selectedSmart != null
          ? selectedSmart.title
          : selectedTag != null
              ? selectedTag.name
              : selectedNotebook?.name ?? 'All Notes',
    };
    // Whenever we're scoped to a specific notebook, tag, smart notebook, or
    // filter view, the folder strip (the only other way back to "All Notes")
    // is hidden — so offer a way back right next to the label it replaced.
    final showBack = filter != null ||
        selectedNotebook != null ||
        selectedTag != null ||
        selectedSmart != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onMenuPressed != null)
                IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: 'Open menu',
                  iconSize: 20,
                  color: cs.onSurfaceVariant,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.only(right: 8),
                  visualDensity: VisualDensity.compact,
                  onPressed: onMenuPressed,
                ),
              if (showBack)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back to All Notes',
                  iconSize: 20,
                  color: cs.onSurfaceVariant,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.only(right: 8),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    ref.read(selectedNotebookIdProvider.notifier).state = null;
                    ref.read(noteFilterProvider.notifier).state = null;
                    ref.read(selectedTagIdProvider.notifier).state = null;
                    ref.read(selectedSmartNotebookIdProvider.notifier).state =
                        null;
                    ref.read(selectedNoteIdProvider.notifier).state = null;
                  },
                ),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$count',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search notes…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: TextStyle(fontSize: 13, color: cs.onSurface),
            onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
            controller: TextEditingController(text: query)
              ..selection = TextSelection(
                baseOffset: query.length,
                extentOffset: query.length,
              ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PopupMenuButton<NoteSortField>(
                tooltip: 'Sort by',
                initialValue: sortField,
                onSelected: (field) => ref
                    .read(noteSortProvider.notifier)
                    .state = (field, ascending),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      value: NoteSortField.updated, child: Text('Date')),
                  PopupMenuItem(
                      value: NoteSortField.title, child: Text('Title')),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sort_rounded,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      sortField == NoteSortField.title ? 'Title' : 'Date',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 15,
                ),
                tooltip: ascending ? 'Ascending' : 'Descending',
                color: cs.onSurfaceVariant,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(6),
                visualDensity: VisualDensity.compact,
                onPressed: () => ref.read(noteSortProvider.notifier).state =
                    (sortField, !ascending),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Folder strip: quick-access notebook cards above the "All Notes" grid ────
//
// Mode/collapsed state lives in providers/folder_strip_provider.dart (not
// private here) so the sidebar's "Smart Notebooks" nav shortcut can switch
// this strip to Smart mode and expand it.

class _FolderStrip extends ConsumerStatefulWidget {
  const _FolderStrip();

  static const _crossAxisCount = 3;
  static const _visibleRows = 2;
  static const _rowHeight = 60.0;
  static const _spacing = 8.0;
  // Padding (10 top + 10 bottom) + N fixed-height rows + the gaps between
  // them — a compact grid, more folders scroll into view underneath.
  static const _stripHeight =
      20.0 + _rowHeight * _visibleRows + _spacing * (_visibleRows - 1);

  @override
  ConsumerState<_FolderStrip> createState() => _FolderStripState();
}

class _FolderStripState extends ConsumerState<_FolderStrip> {
  // See _NoteGridState's controller for why this can't be left implicit —
  // a Scrollbar with no controller crashes on hover if it hasn't yet found
  // a ScrollPosition via bubbled notifications, which desktop hover can
  // easily trigger before any scroll has happened.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];
    final smarts = ref.watch(smartNotebooksProvider).valueOrNull ?? [];
    if (notebooks.isEmpty && tags.isEmpty && smarts.isEmpty) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final collapsed = ref.watch(folderStripCollapsedProvider);
    final mode = ref.watch(folderStripModeProvider);
    final itemCount = switch (mode) {
      FolderStripMode.folders => notebooks.length,
      FolderStripMode.tags => tags.length,
      FolderStripMode.smart => smarts.length,
    };

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => ref
                  .read(folderStripCollapsedProvider.notifier)
                  .state = !collapsed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        switch (mode) {
                          FolderStripMode.folders => 'FOLDERS',
                          FolderStripMode.tags => 'TAGS',
                          FolderStripMode.smart => 'SMART',
                        },
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    if (mode == FolderStripMode.smart)
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 16),
                        tooltip: 'New smart notebook',
                        onPressed: () =>
                            _showCreateSmartNotebookDialog(context, ref),
                        color: cs.onSurfaceVariant,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                      ),
                    const _StripModeToggle(),
                    const SizedBox(width: 8),
                    Icon(
                      collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: _FolderStrip._stripHeight,
                    child: itemCount == 0
                        ? Center(
                            child: Text(
                              switch (mode) {
                                FolderStripMode.folders => 'No folders yet',
                                FolderStripMode.tags => 'No tags yet',
                                FolderStripMode.smart => 'No smart notebooks yet',
                              },
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 12),
                            ),
                          )
                        // Same fix as the note grid below: desktop's default
                        // ScrollBehavior excludes mouse from drag-to-scroll
                        // devices, and this grid has no scrollbar of its own —
                        // without both, a mouse has no way to scroll past the
                        // first rows.
                        : ScrollConfiguration(
                            behavior:
                                ScrollConfiguration.of(context).copyWith(
                              dragDevices: {...PointerDeviceKind.values},
                            ),
                            child: Scrollbar(
                              controller: _scrollController,
                              child: GridView.builder(
                                controller: _scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 2, 16, 10),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _FolderStrip._crossAxisCount,
                                  mainAxisSpacing: _FolderStrip._spacing,
                                  crossAxisSpacing: _FolderStrip._spacing,
                                  mainAxisExtent: _FolderStrip._rowHeight,
                                ),
                                itemCount: itemCount,
                                itemBuilder: (context, i) => switch (mode) {
                                  FolderStripMode.folders =>
                                    _FolderCard(notebook: notebooks[i]),
                                  FolderStripMode.tags => _TagCard(tag: tags[i]),
                                  FolderStripMode.smart =>
                                    _SmartNotebookCard(smart: smarts[i]),
                                },
                              ),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Small two-icon segmented control switching the strip between notebooks
/// and tags. Nested inside the header's own InkWell (which toggles collapse)
/// — Flutter's gesture arena resolves taps to whichever InkWell is innermost,
/// so tapping a segment here never also fires the collapse toggle.
class _StripModeToggle extends ConsumerWidget {
  const _StripModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final mode = ref.watch(folderStripModeProvider);

    Widget segment(FolderStripMode value, IconData icon, String tooltip) {
      final active = mode == value;
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => ref.read(folderStripModeProvider.notifier).state =
              value,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: active ? cs.surfaceContainerHigh : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon,
                size: 14, color: active ? cs.onSurface : cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        segment(FolderStripMode.folders, Icons.folder_rounded, 'Folders'),
        const SizedBox(width: 2),
        segment(FolderStripMode.tags, Icons.sell_rounded, 'Tags'),
        const SizedBox(width: 2),
        segment(FolderStripMode.smart, Icons.auto_awesome_rounded, 'Smart'),
      ],
    );
  }
}

class _FolderCard extends ConsumerWidget {
  final Notebook notebook;
  const _FolderCard({required this.notebook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final color = ref.watch(notebookColorsProvider)[notebook.id] ??
        cs.onSurfaceVariant.withValues(alpha: 0.4);

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(selectedNotebookIdProvider.notifier).state = notebook.id;
          ref.read(selectedNoteIdProvider.notifier).state = null;
          ref.read(noteFilterProvider.notifier).state = null;
          ref.read(selectedTagIdProvider.notifier).state = null;
          ref.read(selectedSmartNotebookIdProvider.notifier).state = null;
          ref.read(mobileTabIndexProvider.notifier).state = 1;
        },
        child: Stack(
          children: [
            // Corner-fold tab — the reference screenshots' signature
            // folder-card accent.
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 26,
                height: 11,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${notebook.noteCount}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notebook.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagCard extends ConsumerWidget {
  final Tag tag;
  const _TagCard({required this.tag});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(selectedTagIdProvider.notifier).state = tag.id;
          ref.read(selectedNotebookIdProvider.notifier).state = null;
          ref.read(selectedNoteIdProvider.notifier).state = null;
          ref.read(noteFilterProvider.notifier).state = null;
          ref.read(selectedSmartNotebookIdProvider.notifier).state = null;
          ref.read(mobileTabIndexProvider.notifier).state = 1;
        },
        child: Stack(
          children: [
            // Same corner-fold accent as _FolderCard, just a fixed color —
            // tags (unlike notebooks) have no per-item color picker.
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 26,
                height: 11,
                decoration: BoxDecoration(
                  color: cs.secondary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${tag.count}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartNotebookCard extends ConsumerWidget {
  final SmartNotebook smart;
  const _SmartNotebookCard({required this.smart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(selectedSmartNotebookIdProvider.notifier).state = smart.id;
          ref.read(selectedNotebookIdProvider.notifier).state = null;
          ref.read(selectedTagIdProvider.notifier).state = null;
          ref.read(selectedNoteIdProvider.notifier).state = null;
          ref.read(noteFilterProvider.notifier).state = null;
          ref.read(mobileTabIndexProvider.notifier).state = 1;
        },
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 26,
                height: 11,
                decoration: BoxDecoration(
                  color: cs.tertiary,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(height: 2),
                  Text(
                    smart.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create smart notebook dialog ─────────────────────────────────────────────

void _showCreateSmartNotebookDialog(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (context) => const _CreateSmartNotebookDialog(),
  );
}

class _CreateSmartNotebookDialog extends ConsumerStatefulWidget {
  const _CreateSmartNotebookDialog();

  @override
  ConsumerState<_CreateSmartNotebookDialog> createState() =>
      _CreateSmartNotebookDialogState();
}

class _CreateSmartNotebookDialogState
    extends ConsumerState<_CreateSmartNotebookDialog> {
  final _titleController = TextEditingController();
  final _keywordController = TextEditingController();
  final _innerTitleController = TextEditingController();
  final _selectedTagNames = <String>{};
  String _tagOperator = 'and';
  String? _notebookId;
  bool _busy = false;

  @override
  void dispose() {
    _titleController.dispose();
    _keywordController.dispose();
    _innerTitleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);
    try {
      await createSmartNotebook(
        ref,
        title: title,
        criteria: SmartCriteria(
          keyword: _keywordController.text.trim().isEmpty
              ? null
              : _keywordController.text.trim(),
          innerTitle: _innerTitleController.text.trim().isEmpty
              ? null
              : _innerTitleController.text.trim(),
          tagNames: _selectedTagNames.toList(),
          tagOperator: _tagOperator,
          notebookIds: _notebookId == null ? const [] : [_notebookId!],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Create smart notebook failed: $e');
      if (mounted) {
        AppToast.error(context, 'Could not create the smart notebook.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider).valueOrNull ?? [];
    final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];

    return AlertDialog(
      title: const Text('New Smart Notebook'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keywordController,
                decoration: const InputDecoration(
                  labelText: 'Keyword (searches note content)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _innerTitleController,
                decoration: const InputDecoration(
                  labelText: 'Title contains',
                ),
              ),
              if (notebooks.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _notebookId,
                  decoration:
                      const InputDecoration(labelText: 'Restrict to notebook'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any')),
                    ...notebooks.map((nb) =>
                        DropdownMenuItem(value: nb.id, child: Text(nb.name))),
                  ],
                  onChanged: (v) => setState(() => _notebookId = v),
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tags',
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags.map((t) {
                    final selected = _selectedTagNames.contains(t.name);
                    return FilterChip(
                      label: Text(t.name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedTagNames.add(t.name);
                        } else {
                          _selectedTagNames.remove(t.name);
                        }
                      }),
                    );
                  }).toList(),
                ),
                if (_selectedTagNames.length > 1) ...[
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'and', label: Text('Match all')),
                      ButtonSegment(value: 'or', label: Text('Match any')),
                    ],
                    selected: {_tagOperator},
                    onSelectionChanged: (s) =>
                        setState(() => _tagOperator = s.first),
                  ),
                ],
              ],
            ],
          ),
        ),
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
              : const Text('Create'),
        ),
      ],
    );
  }
}

// ── Note grid (masonry) ───────────────────────────────────────────────────────

class _NoteGrid extends StatefulWidget {
  final List<Note> notes;
  final String? selectedId;
  const _NoteGrid({required this.notes, required this.selectedId});

  @override
  State<_NoteGrid> createState() => _NoteGridState();
}

class _NoteGridState extends State<_NoteGrid> {
  // A Scrollbar given no controller falls back to locating its Scrollable
  // via bubbled ScrollNotifications (or the PrimaryScrollController, which
  // desktop ScrollViews don't auto-attach to at all) — fragile enough that
  // a hover before any scroll notification has ever fired crashes the
  // animation library outright. Owning the controller explicitly and
  // handing the *same instance* to both the grid and the Scrollbar sidesteps
  // that lookup entirely.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 170).floor().clamp(1, 4);
        // Flutter's default desktop ScrollBehavior only allows drag-to-scroll
        // from touch/stylus/trackpad, not mouse — and a masonry grid has no
        // scrollbar of its own. Without both of these, there is no way to
        // scroll this grid with a mouse at all (wheel is unaffected by
        // either, but isn't a substitute for a discoverable drag affordance).
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {...PointerDeviceKind.values},
          ),
          child: Scrollbar(
            controller: _scrollController,
            child: MasonryGridView.count(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              itemCount: widget.notes.length,
              itemBuilder: (context, i) {
                return Consumer(
                  builder: (context, ref, _) => _NoteCard(
                    note: widget.notes[i],
                    isSelected: widget.notes[i].id == widget.selectedId,
                    onTap: () {
                      ref.read(selectedNoteIdProvider.notifier).state =
                          widget.notes[i].id;
                      ref.read(mobileTabIndexProvider.notifier).state = 2;
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _NoteCard extends ConsumerWidget {
  final Note note;
  final bool isSelected;
  final VoidCallback onTap;

  const _NoteCard({
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
    final noteColorLabel = noteColor == null
        ? null
        : ref.watch(colorLabelsProvider)[noteColor.toARGB32()];

    final resolvedTags =
        note.tags.map((id) => tagNames[id] ?? id).take(3).toList();

    return Material(
      color:
          isSelected ? cs.primaryContainer.withValues(alpha: 0.3) : cs.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (noteColor != null) Container(height: 4, color: noteColor),
              Padding(
                padding:
                    EdgeInsets.fromLTRB(12, noteColor != null ? 8 : 12, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (note.isPinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 4, top: 2),
                            child: Icon(Icons.push_pin_rounded,
                                size: 12, color: cs.primary),
                          ),
                        if (note.isFavorite)
                          const Padding(
                            padding: EdgeInsets.only(right: 4, top: 2),
                            child: Icon(Icons.star_rounded,
                                size: 12, color: Color(0xFFF59E0B)),
                          ),
                        if (note.isEncrypted)
                          Padding(
                            padding: const EdgeInsets.only(right: 4, top: 2),
                            child: Icon(Icons.lock_rounded,
                                size: 12, color: cs.onSurfaceVariant),
                          ),
                        Expanded(
                          child: Text(
                            note.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (note.displayExcerpt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        note.displayExcerpt,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                        maxLines: 5,
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dateStr,
                            style: TextStyle(
                                fontSize: 10.5, color: cs.onSurfaceVariant),
                          ),
                        ),
                        Builder(builder: (context) {
                          final inTrash =
                              ref.watch(noteFilterProvider) == NoteFilter.trash;
                          return PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded,
                                size: 16, color: cs.onSurfaceVariant),
                            tooltip: 'Note actions',
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            onSelected: (action) {
                              if (action == 'color') {
                                showColorPicker(context, ref,
                                    id: note.id,
                                    colorsProvider: noteColorsProvider);
                              } else if (action == 'delete') {
                                _confirmDeleteNote(context, ref, note);
                              } else if (action == 'restore') {
                                _restoreNote(context, ref, note);
                              } else if (action == 'purge') {
                                _confirmPurgeNote(context, ref, note);
                              }
                            },
                            itemBuilder: (context) => inTrash
                                ? const [
                                    PopupMenuItem(
                                        value: 'restore',
                                        child: Text('Restore')),
                                    PopupMenuItem(
                                        value: 'purge',
                                        child: Text('Delete Forever')),
                                  ]
                                : [
                                    PopupMenuItem(
                                      value: 'color',
                                      child: Text(noteColorLabel ?? 'Set Color'),
                                    ),
                                    const PopupMenuItem(
                                        value: 'delete', child: Text('Delete')),
                                  ],
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
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
  final NoteFilter? filter;
  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final message = switch (filter) {
      NoteFilter.favorites => 'No favorite notes yet',
      NoteFilter.locked => 'No locked notes',
      NoteFilter.shared => 'No shared notes',
      NoteFilter.trash => 'Trash is empty',
      null => ref.watch(selectedNotebookProvider) != null
          ? 'No notes in this notebook'
          : 'No notes found',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: cs.onSurfaceVariant)),
          if (filter == null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _createNote(context, ref),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('New Note'),
            ),
          ],
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
              syncAfterMutation(ref);
              if (context.mounted) {
                AppToast.success(
                  context,
                  isLocal ? 'Note deleted' : 'Moved to trash',
                );
              }
            } catch (e) {
              debugPrint('Delete note failed: $e');
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

// ── Trash: restore / permanently delete (NAS-only) ──────────────────────────

Future<void> _restoreNote(BuildContext context, WidgetRef ref, Note note) async {
  final repo = ref.read(repositoryProvider);
  if (repo == null) return;
  try {
    await repo.restoreNote(note.id);
    syncAfterMutation(ref);
    if (context.mounted) AppToast.success(context, 'Note restored');
  } catch (e) {
    debugPrint('Restore note failed: $e');
    if (context.mounted) AppToast.error(context, 'Could not restore the note.');
  }
}

void _confirmPurgeNote(BuildContext context, WidgetRef ref, Note note) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Forever?'),
      content: Text(
          'Permanently delete "${note.title}"? This cannot be undone.'),
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
              await repo.purgeNote(note.id);
              if (ref.read(selectedNoteIdProvider) == note.id) {
                ref.read(selectedNoteIdProvider.notifier).state = null;
              }
              syncAfterMutation(ref);
              if (context.mounted) {
                AppToast.success(context, 'Note permanently deleted');
              }
            } catch (e) {
              debugPrint('Purge note failed: $e');
              if (context.mounted) {
                AppToast.error(context, 'Could not permanently delete the note.');
              }
            }
          },
          child: const Text('Delete Forever'),
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
    final note =
        await repo.createNote(notebookId: notebookId, title: 'Untitled Note');
    syncAfterMutation(ref);
    ref.read(selectedNotebookIdProvider.notifier).state = notebookId;
    ref.read(noteFilterProvider.notifier).state = null;
    ref.read(selectedNoteIdProvider.notifier).state = note.id;
    ref.read(mobileTabIndexProvider.notifier).state = 2;
    progress.close();
  } catch (e) {
    debugPrint('Create note failed: $e');
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
