import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_mode_provider.dart';
import '../providers/notes_provider.dart';
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
// never floats on top of note cards a user is trying to scroll through. It
// hides itself while a note is actively being edited (noteEditingProvider)
// so it doesn't obstruct the editor toolbar/content instead.
class _EditorPanel extends ConsumerWidget {
  const _EditorPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = ref.watch(noteEditingProvider);
    return Stack(
      children: [
        const NoteEditor(),
        if (!editing)
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
            message: isOffline
                ? 'Offline Mode'
                : (session?.username ?? 'Not connected'),
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
      // No AppBar — the hamburger that used to live there now sits inline in
      // NoteList's own header, to the left of "All Notes", instead of
      // pushing it down the screen with a whole extra bar just for one
      // icon. SafeArea replaces the top-inset handling the AppBar used to
      // provide implicitly (bottom is left alone; nothing here needs it).
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            SizedBox(
              width: 260,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: NoteList(
                    onMenuPressed: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                  ),
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
      ),
    );
  }
}

// ── Mobile: bottom nav ───────────────────────────────────────────────────────

class _MobileLayout extends ConsumerWidget {
  const _MobileLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(mobileTabIndexProvider);
    // No app title bar, to give notes maximum vertical space. While a note
    // is actively being edited, the tab bar hides too — otherwise it would
    // sit sandwiched between the formatting toolbar and the keyboard (the
    // keyboard pushes the whole Scaffold, including bottomNavigationBar, up
    // with it), which wastes space and doesn't match the single anchored
    // toolbar Samsung Notes shows while editing.
    final editingNote = ref.watch(noteEditingProvider);
    return Scaffold(
      // With no AppBar, nothing else accounts for the status bar inset
      // (AppBar used to do this implicitly) — without this, headers like
      // NoteList's "All Notes" or the editor's meta row render underneath
      // the system status bar. bottom is left to Scaffold's own handling
      // (NavigationBar / the keyboard-anchored toolbar), so it's not
      // double-padded here.
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: tab,
          children: const [
            AppSidebar(),
            NoteList(),
            _EditorPanel(),
          ],
        ),
      ),
      bottomNavigationBar: editingNote
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) =>
                  ref.read(mobileTabIndexProvider.notifier).state = i,
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
