import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_mode_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/sidebar/sidebar.dart';
import '../widgets/note_list/note_list.dart' show NoteList, NewNoteFab;
import '../widgets/note_editor/note_editor.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final isMedium = MediaQuery.sizeOf(context).width >= 600;

    if (isWide) return const _ThreePanelLayout();
    if (isMedium) return const _TwoPanelLayout();
    return const _MobileLayout();
  }
}

// ── Wide (desktop / tablet landscape): sidebar | note list | editor ──────────

class _ThreePanelLayout extends ConsumerWidget {
  const _ThreePanelLayout();

  static const _sidebarExpandedWidth = 220.0;
  static const _sidebarCollapsedWidth = 40.0;
  static const _noteListBaseWidth = 280.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final cs = Theme.of(context).colorScheme;

    // When the sidebar collapses, the note list grows by exactly the width
    // it freed up — a direct swap, so the editor's own width is unaffected —
    // giving the folder strip and note grid more room to show more at once.
    final noteListWidth = collapsed
        ? _noteListBaseWidth + (_sidebarExpandedWidth - _sidebarCollapsedWidth)
        : _noteListBaseWidth;

    return Scaffold(
      // Panels sit on a slightly darker page background and read as
      // distinct soft-edged sections (a thin gap + rounded corners) rather
      // than being separated by hard dividing lines.
      backgroundColor: cs.surfaceContainerLowest,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            width: collapsed ? _sidebarCollapsedWidth : _sidebarExpandedWidth,
            child: ClipRect(
              child: collapsed
                  ? _CollapsedRail(
                      onExpand: () => ref
                          .read(sidebarCollapsedProvider.notifier)
                          .state = false,
                    )
                  // The AnimatedContainer's width animates through
                  // intermediate values (40→220) on expand, and AppSidebar's
                  // contents aren't designed to lay out narrower than 220. A
                  // plain SizedBox(width: 220) isn't enough here — its "fixed"
                  // width still gets clamped down to whatever (narrower) max
                  // width the parent currently allows. OverflowBox instead
                  // forces the child to lay out at exactly 220 regardless of
                  // the incoming constraints, letting it visually overflow
                  // its box — which ClipRect then crops during the
                  // transition, instead of forcing a relayout that overflows.
                  : const OverflowBox(
                      minWidth: _sidebarExpandedWidth,
                      maxWidth: _sidebarExpandedWidth,
                      alignment: Alignment.centerLeft,
                      child: AppSidebar(),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            width: noteListWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const NoteList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const _EditorPanel(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// The editor panel hosts the "new note" FAB (not the note list panel) so it
// never floats on top of note cards a user is trying to scroll through.
class _EditorPanel extends StatelessWidget {
  const _EditorPanel();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const NoteEditor(),
        Positioned(
          right: 16,
          bottom: 16,
          child: NewNoteFab(),
        ),
      ],
    );
  }
}

// Thin rail shown when the sidebar is collapsed.
class _CollapsedRail extends ConsumerWidget {
  final VoidCallback onExpand;
  const _CollapsedRail({required this.onExpand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final mode = ref.watch(appModeProvider);
    final session = ref.watch(sessionProvider);
    final isOffline = mode == AppMode.local;
    final isConnected = !isOffline && session != null;

    return Container(
      color: cs.surfaceContainerLow,
      width: 40,
      child: Column(
        children: [
          const SizedBox(height: 10),
          // App logo icon — mirrors the sidebar header avatar.
          // TEMPORARY: placeholder app mark while the real design gets
          // finalized — swaps out the mode-colored customizable icon below
          // rather than deleting it, so restoring it later is a one-line
          // revert. Keep in sync with _SidebarHeader in sidebar.dart.
          Tooltip(
            message: isOffline ? 'Offline Mode' : (session?.username ?? 'Not connected'),
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            // child: Container(
            //   width: 32,
            //   height: 32,
            //   decoration: BoxDecoration(
            //     color: isOffline ? cs.secondaryContainer : cs.primary,
            //     borderRadius: BorderRadius.circular(8),
            //   ),
            //   child: Icon(
            //     isOffline ? Icons.phone_android_rounded : Icons.note_alt_rounded,
            //     color: isOffline ? cs.onSecondaryContainer : cs.onPrimary,
            //     size: 18,
            //   ),
            // ),
          ),
          const SizedBox(height: 4),
          // Expand button
          IconButton(
            icon: Icon(Icons.chevron_right_rounded,
                size: 20, color: cs.onSurfaceVariant),
            onPressed: onExpand,
            tooltip: 'Expand sidebar',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8),
          ),
          const Spacer(),
          // Connectivity dot — green = connected, red = offline/disconnected
          Tooltip(
            message: isConnected ? 'Connected to ${session.host}' : 'Offline',
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: isConnected ? const Color(0xFF4CAF50) : cs.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Medium (tablet portrait): note list | editor, sidebar in drawer ──────────

class _TwoPanelLayout extends ConsumerStatefulWidget {
  const _TwoPanelLayout();

  @override
  ConsumerState<_TwoPanelLayout> createState() => _TwoPanelLayoutState();
}

class _TwoPanelLayoutState extends ConsumerState<_TwoPanelLayout> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surfaceContainerLowest,
      drawer: const SizedBox(width: 240, child: Drawer(child: AppSidebar())),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: const Text('Synology Notes Enhanced'),
        actions: const [_AppBarActions()],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const NoteList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: const _EditorPanel(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile: bottom nav ───────────────────────────────────────────────────────

class _MobileLayout extends ConsumerStatefulWidget {
  const _MobileLayout();

  @override
  ConsumerState<_MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends ConsumerState<_MobileLayout> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synology Notes Enhanced'),
        actions: const [_AppBarActions()],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          AppSidebar(),
          NoteList(),
          _EditorPanel(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Notebooks',
          ),
          NavigationDestination(
            icon: Icon(Icons.notes_outlined),
            selectedIcon: Icon(Icons.notes_rounded),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_outlined),
            selectedIcon: Icon(Icons.edit_rounded),
            label: 'Editor',
          ),
        ],
      ),
    );
  }
}

// ── AppBar actions: settings always visible, sign-out only in NAS mode ───────

class _AppBarActions extends ConsumerWidget {
  const _AppBarActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(appModeProvider) == AppMode.local;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
        if (!isOffline)
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              ref.read(appModeProvider.notifier).state = AppMode.local;
              if (context.mounted) context.go('/home');
            },
          ),
      ],
    );
  }
}
