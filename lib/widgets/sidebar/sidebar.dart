import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/notebook.dart';
import '../../models/shelf.dart';
import '../../providers/app_mode_provider.dart'
    show AppMode, appModeProvider, sidebarCollapsedProvider;
import '../../providers/notebooks_provider.dart';
import '../../providers/notes_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/shelves_provider.dart';

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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
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
    return _SidebarTile(
      icon: notebook.isShared
          ? Icons.folder_shared_rounded
          : Icons.folder_rounded,
      label: notebook.name,
      count: notebook.noteCount,
      isSelected: isSelected,
      onTap: () {
        ref.read(selectedNotebookIdProvider.notifier).state = notebook.id;
        ref.read(selectedNoteIdProvider.notifier).state = null;
      },
    );
  }
}

// ── Sidebar tile ──────────────────────────────────────────────────────────────

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
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
                  color: isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
