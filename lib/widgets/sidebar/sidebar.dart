import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/notebook.dart';
import '../../models/shelf.dart';
import '../../providers/app_mode_provider.dart'
    show AppMode, appModeProvider, sidebarCollapsedProvider, repositoryProvider;
import '../../providers/notebooks_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/note_color_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/shelves_provider.dart';
import '../common/app_toast.dart';

class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notebooksAsync = ref.watch(notebooksProvider);
    final shelvesAsync = ref.watch(shelvesProvider);
    final selectedId = ref.watch(selectedNotebookIdProvider);
    final session = ref.watch(sessionProvider);
    final mode = ref.watch(appModeProvider);

    final displayName = session?.username ??
        (mode == AppMode.local ? 'Offline Mode' : 'Not Connected');

    return Container(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          _SidebarHeader(displayName: displayName, isOffline: mode == AppMode.local),
          Divider(color: cs.outlineVariant, height: 1),
          _AllNotesItem(isSelected: selectedId == null),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'NOTEBOOKS',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  tooltip: 'New Notebook',
                  onPressed: () => _showNewNotebookDialog(context, ref),
                  color: cs.onSurfaceVariant,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: notebooksAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load notebooks',
                      style: TextStyle(color: cs.error, fontSize: 12),
                      textAlign: TextAlign.center),
                ),
              ),
              data: (notebooks) {
                final shelves = shelvesAsync.valueOrNull ?? [];
                return _NotebookTree(
                  notebooks: notebooks,
                  shelves: shelves,
                  selectedId: selectedId,
                );
              },
            ),
          ),
          Divider(color: cs.outlineVariant, height: 1),
          _SidebarFooter(session: session, mode: mode),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _SidebarHeader extends ConsumerWidget {
  final String displayName;
  final bool isOffline;
  const _SidebarHeader({required this.displayName, required this.isOffline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isOffline ? cs.secondaryContainer : cs.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isOffline ? Icons.phone_android_rounded : Icons.note_alt_rounded,
              color: isOffline ? cs.onSecondaryContainer : cs.onPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Synology Notes Enhanced',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  displayName,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_left_rounded,
                size: 18, color: cs.onSurfaceVariant),
            onPressed: () =>
                ref.read(sidebarCollapsedProvider.notifier).state = true,
            tooltip: 'Collapse sidebar',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(6),
          ),
        ],
      ),
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _SidebarFooter extends ConsumerWidget {
  final dynamic session;
  final AppMode? mode;
  const _SidebarFooter({this.session, this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isOffline = mode == AppMode.local;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Connection status indicator
          if (!isOffline && session != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF4CAF50),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                session.host,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),

          // Sync — only in NAS mode
          if (!isOffline) ...[
            _FooterIconButton(
              icon: Icons.sync_rounded,
              tooltip: 'Sync',
              onPressed: () {
                ref.invalidate(notebooksProvider);
                ref.invalidate(shelvesProvider);
                ref.invalidate(notesProvider);
              },
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
          ],

          // Settings — always visible
          _FooterIconButton(
            icon: Icons.settings_rounded,
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            color: cs.onSurfaceVariant,
          ),

          // Sign Out — only in NAS mode
          if (!isOffline) ...[
            const SizedBox(width: 4),
            _FooterIconButton(
              icon: Icons.logout_rounded,
              tooltip: 'Sign Out',
              onPressed: () async {
                await ref.read(sessionProvider.notifier).logout();
                ref.read(appModeProvider.notifier).state = AppMode.local;
                if (context.mounted) context.go('/home');
              },
              color: cs.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _FooterIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;

  const _FooterIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 18),
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: const BoxConstraints(),
      padding: EdgeInsets.zero,
    );
  }
}

// ── All Notes item ────────────────────────────────────────────────────────────

class _AllNotesItem extends ConsumerWidget {
  final bool isSelected;
  const _AllNotesItem({required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(allNotesCountProvider);
    return _SidebarTile(
      icon: Icons.notes_rounded,
      label: 'All Notes',
      count: total,
      isSelected: isSelected,
      onTap: () {
        ref.read(selectedNotebookIdProvider.notifier).state = null;
        ref.read(selectedNoteIdProvider.notifier).state = null;
      },
    );
  }
}

// ── Notebook tree ─────────────────────────────────────────────────────────────

class _NotebookTree extends ConsumerWidget {
  final List<Notebook> notebooks;
  final List<Shelf> shelves;
  final String? selectedId;

  const _NotebookTree({
    required this.notebooks,
    required this.shelves,
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unshelved = notebooks.where((n) => n.shelfId == null).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final shelf in shelves) ...[
          _ShelfHeader(shelf: shelf),
          for (final nb in notebooks.where((n) => n.shelfId == shelf.id))
            _NotebookItem(notebook: nb, isSelected: nb.id == selectedId),
        ],
        for (final nb in unshelved)
          _NotebookItem(notebook: nb, isSelected: nb.id == selectedId),
      ],
    );
  }
}

class _ShelfHeader extends StatelessWidget {
  final Shelf shelf;
  const _ShelfHeader({required this.shelf});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          Icon(Icons.library_books_rounded, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              shelf.name.toUpperCase(),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookItem extends ConsumerWidget {
  final Notebook notebook;
  final bool isSelected;
  const _NotebookItem({required this.notebook, required this.isSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notebookColor = ref.watch(notebookColorsProvider)[notebook.id];
    return _SidebarTile(
      icon: notebook.isShared
          ? Icons.folder_shared_rounded
          : Icons.folder_rounded,
      iconColor: notebookColor,
      label: notebook.name,
      count: notebook.noteCount,
      isSelected: isSelected,
      onTap: () {
        ref.read(selectedNotebookIdProvider.notifier).state = notebook.id;
        ref.read(selectedNoteIdProvider.notifier).state = null;
      },
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, size: 16, color: cs.onSurfaceVariant),
        tooltip: 'Notebook actions',
        constraints: const BoxConstraints(),
        padding: EdgeInsets.zero,
        onSelected: (action) {
          if (action == 'rename') {
            _showRenameNotebookDialog(context, ref, notebook);
          } else if (action == 'color') {
            showColorPicker(context, ref,
                id: notebook.id, colorsProvider: notebookColorsProvider);
          } else if (action == 'delete') {
            _showDeleteNotebookDialog(context, ref, notebook);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'color', child: Text('Color')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

// ── Sidebar tile ──────────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SidebarTile({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isSelected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: iconColor ??
                      (isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? cs.onSecondaryContainer : cs.onSurface,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: TextStyle(
                      color: isSelected
                          ? cs.onSecondaryContainer.withValues(alpha: 0.7)
                          : cs.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notebook dialogs ────────────────────────────────────────────────────────

void _showNewNotebookDialog(BuildContext context, WidgetRef ref) {
  // Captured under its own name — the dialog's `builder` below introduces its
  // own `context` for the same identifier, which would otherwise shadow this
  // one (the caller's, still valid after the dialog pops) inside onConfirm.
  final callerContext = context;
  showDialog<void>(
    context: context,
    builder: (context) => _NotebookFormDialog(
      title: 'New Notebook',
      confirmLabel: 'Create',
      onConfirm: (name, shelfId) async {
        final repo = ref.read(repositoryProvider);
        if (repo == null) return;
        final nb = await repo.createNotebook(title: name, shelfId: shelfId);
        ref.invalidate(notebooksProvider);
        ref.invalidate(shelvesProvider);
        ref.read(selectedNotebookIdProvider.notifier).state = nb.id;
        if (callerContext.mounted) {
          AppToast.success(callerContext, 'Created "${nb.name}"');
        }
      },
    ),
  );
}

void _showRenameNotebookDialog(
    BuildContext context, WidgetRef ref, Notebook notebook) {
  final callerContext = context;
  showDialog<void>(
    context: context,
    builder: (context) => _NotebookFormDialog(
      title: 'Rename Notebook',
      confirmLabel: 'Save',
      initialName: notebook.name,
      showShelfPicker: false,
      onConfirm: (name, _) async {
        final repo = ref.read(repositoryProvider);
        if (repo == null) return;
        await repo.renameNotebook(notebookId: notebook.id, title: name);
        ref.invalidate(notebooksProvider);
        if (callerContext.mounted) {
          AppToast.success(callerContext, 'Renamed to "$name"');
        }
      },
    ),
  );
}

void _showDeleteNotebookDialog(
    BuildContext context, WidgetRef ref, Notebook notebook) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Notebook?'),
      content: Text(
        notebook.noteCount > 0
            ? 'Delete "${notebook.name}" and its ${notebook.noteCount} '
                'note(s)? This cannot be undone.'
            : 'Delete "${notebook.name}"? This cannot be undone.',
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
              await repo.deleteNotebook(notebook.id);
              if (ref.read(selectedNotebookIdProvider) == notebook.id) {
                ref.read(selectedNotebookIdProvider.notifier).state = null;
                ref.read(selectedNoteIdProvider.notifier).state = null;
              }
              ref.invalidate(notebooksProvider);
              ref.invalidate(notesProvider);
              if (context.mounted) {
                AppToast.success(context, 'Deleted "${notebook.name}"');
              }
            } catch (_) {
              if (context.mounted) {
                AppToast.error(context, 'Could not delete the notebook.');
              }
            }
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

// Shared name (+ optional shelf) form used for create and rename.
class _NotebookFormDialog extends ConsumerStatefulWidget {
  final String title;
  final String confirmLabel;
  final String? initialName;
  final bool showShelfPicker;
  final Future<void> Function(String name, String? shelfId) onConfirm;

  const _NotebookFormDialog({
    required this.title,
    required this.confirmLabel,
    required this.onConfirm,
    this.initialName,
    this.showShelfPicker = true,
  });

  @override
  ConsumerState<_NotebookFormDialog> createState() =>
      _NotebookFormDialogState();
}

class _NotebookFormDialogState extends ConsumerState<_NotebookFormDialog> {
  late final _controller =
      TextEditingController(text: widget.initialName ?? '');
  String? _shelfId;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm(name, _shelfId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        AppToast.error(context, 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelves = widget.showShelfPicker
        ? ref.watch(shelvesProvider).valueOrNull ?? const <Shelf>[]
        : const <Shelf>[];

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.showShelfPicker && shelves.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _shelfId,
              decoration: const InputDecoration(labelText: 'Shelf (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...shelves.map(
                  (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                ),
              ],
              onChanged: (v) => setState(() => _shelfId = v),
            ),
          ],
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
              : Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
