import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/services/nsx_service.dart';
import '../providers/session_provider.dart';
import '../providers/app_mode_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/shelves_provider.dart';
import '../providers/tags_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/stats_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final session = ref.watch(sessionProvider);
    final mode = ref.watch(appModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      backgroundColor: cs.surface,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Storage Mode'),
          _ModeSelector(currentMode: mode),
          const Divider(indent: 16, endIndent: 16),
          if (mode == AppMode.nas || mode == null) ...[
            _SectionHeader('Synology NAS'),
            _NasConnectionTile(session: session),
            const Divider(indent: 16, endIndent: 16),
          ],
          _SectionHeader('Library'),
          const _StatsGrid(),
          const _ResyncButton(),
          const Divider(indent: 16, endIndent: 16),
          _SectionHeader('Import / Export'),
          const _NsxImportExport(),
          const Divider(indent: 16, endIndent: 16),
          _SectionHeader('About'),
          const _AboutTile(),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

// ── Mode selector ──────────────────────────────────────────────────────────────

class _ModeSelector extends ConsumerWidget {
  final AppMode? currentMode;
  const _ModeSelector({required this.currentMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return RadioGroup<AppMode>(
      groupValue: currentMode,
      onChanged: (v) {
        if (v == null) return;
        if (v == AppMode.nas) {
          // Navigate to login with force=true so the auth redirect doesn't
          // bounce an already-authenticated (offline) user back to /home.
          context.push('/login?force=true');
          return;
        }
        ref.read(appModeProvider.notifier).state = v;
        _invalidateAll(ref);
      },
      child: Column(
        children: [
          RadioListTile<AppMode>(
            title: const Text('Synology NAS'),
            subtitle: const Text('Sync notes with your Synology NAS'),
            value: AppMode.nas,
            secondary: Icon(Icons.cloud_rounded, color: cs.primary),
          ),
          RadioListTile<AppMode>(
            title: const Text('Offline Mode'),
            subtitle: const Text('Store notes locally on this device'),
            value: AppMode.local,
            secondary: Icon(Icons.phone_android_rounded, color: cs.secondary),
          ),
        ],
      ),
    );
  }

  void _invalidateAll(WidgetRef ref) {
    ref.invalidate(notebooksProvider);
    ref.invalidate(shelvesProvider);
    ref.invalidate(notesProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(selectedNoteIdProvider);
    ref.invalidate(selectedNotebookIdProvider);
  }
}

// ── NAS connection tile ────────────────────────────────────────────────────────

class _NasConnectionTile extends ConsumerWidget {
  final dynamic session;
  const _NasConnectionTile({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    if (session != null) {
      return ListTile(
        leading: Icon(Icons.check_circle_rounded, color: cs.primary),
        title: Text('Connected as ${session.username}'),
        subtitle: Text(session.baseUrl),
        trailing: TextButton(
          onPressed: () async {
            await ref.read(sessionProvider.notifier).logout();
            ref.read(appModeProvider.notifier).state = AppMode.local;
            if (context.mounted) context.go('/home');
          },
          child: const Text('Sign Out'),
        ),
      );
    }

    return ListTile(
      leading: Icon(Icons.cloud_off_rounded, color: cs.onSurfaceVariant),
      title: const Text('Not connected'),
      subtitle: const Text('Sign in to sync with your NAS'),
      trailing: FilledButton.tonal(
        onPressed: () => context.push('/login?force=true'),
        child: const Text('Sign In'),
      ),
    );
  }
}

// ── Stats grid ─────────────────────────────────────────────────────────────────

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allNotesAsync = ref.watch(notesProvider);
    final notebooksAsync = ref.watch(notebooksProvider);

    final totalNotes = allNotesAsync.valueOrNull?.length;
    final starred = totalNotes == null ? null : ref.watch(starredNotesCountProvider);
    final todos = ref.watch(todosCountProvider);
    final userNotebooks = notebooksAsync.valueOrNull == null
        ? null
        : ref.watch(userNotebooksCountProvider);
    final sharedNotebooks = notebooksAsync.valueOrNull == null
        ? null
        : ref.watch(sharedNotebooksCountProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final tagsCount = tagsAsync.valueOrNull == null
        ? null
        : ref.watch(tagsCountProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              _StatCell(label: 'Notes', value: totalNotes),
              _StatCell(label: 'Starred', value: starred),
              _StatCell(label: 'To-Do Lists', value: todos, isStub: true),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatCell(label: 'Notebooks', value: userNotebooks),
              _StatCell(label: 'Joined', value: sharedNotebooks),
              _StatCell(label: 'Tags', value: tagsCount),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final int? value;
  final bool isStub;

  const _StatCell({
    required this.label,
    required this.value,
    this.isStub = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            isStub
                ? Text(
                    '–',
                    style: tt.titleLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : value == null
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : Text(
                        '$value',
                        style: tt.titleLarge?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
            const SizedBox(height: 4),
            Text(
              label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Re-sync button ─────────────────────────────────────────────────────────────

class _ResyncButton extends ConsumerWidget {
  const _ResyncButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final isNas = mode == AppMode.nas;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.sync_rounded),
          label: Text(isNas ? 'Re-sync with NAS' : 'Refresh Local Data'),
          onPressed: () {
            ref.invalidate(notebooksProvider);
            ref.invalidate(shelvesProvider);
            ref.invalidate(notesProvider);
            ref.invalidate(tagsProvider);
            ref.invalidate(selectedNoteIdProvider);
            ref.invalidate(selectedNotebookIdProvider);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isNas ? 'Syncing with NAS…' : 'Refreshing local data…'),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── .nsx import / export ─────────────────────────────────────────────────────────

class _NsxImportExport extends ConsumerStatefulWidget {
  const _NsxImportExport();

  @override
  ConsumerState<_NsxImportExport> createState() => _NsxImportExportState();
}

class _NsxImportExportState extends ConsumerState<_NsxImportExport> {
  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['nsx'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes ??
        (file.path != null ? File(file.path!).readAsBytesSync() : null);
    if (bytes == null) {
      _snack('Could not read the selected file.');
      return;
    }

    setState(() => _busy = true);
    try {
      final (nb, notes) = await NsxService.importToLocal(bytes);
      // Imported into offline storage — switch to local mode so it's visible.
      ref.read(appModeProvider.notifier).state = AppMode.local;
      _invalidateAll(ref);
      _snack('Imported $notes note(s) and $nb notebook(s) into offline storage.');
    } catch (e) {
      _snack('Import failed: not a valid .nsx file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) {
      _snack('Nothing to export.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await NsxService.exportFrom(repo);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .substring(0, 19);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export notes as .nsx',
        fileName: 'SynologyNotes_$stamp.nsx',
        type: FileType.custom,
        allowedExtensions: ['nsx'],
        bytes: bytes,
      );
      if (path == null) return; // cancelled
      // On desktop saveFile returns a path but doesn't write; write here.
      final f = File(path);
      if (!f.existsSync() || f.lengthSync() == 0) f.writeAsBytesSync(bytes);
      _snack('Exported to $path');
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateAll(WidgetRef ref) {
    ref.invalidate(notebooksProvider);
    ref.invalidate(shelvesProvider);
    ref.invalidate(notesProvider);
    ref.invalidate(tagsProvider);
    ref.invalidate(selectedNoteIdProvider);
    ref.invalidate(selectedNotebookIdProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          leading: Icon(Icons.file_download_rounded, color: cs.primary),
          title: const Text('Import .nsx…'),
          subtitle:
              const Text('Load a Note Station export into offline storage'),
          enabled: !_busy,
          onTap: _busy ? null : _import,
        ),
        ListTile(
          leading: Icon(Icons.file_upload_rounded, color: cs.primary),
          title: const Text('Export .nsx…'),
          subtitle: const Text('Save all current notes as a .nsx bundle'),
          enabled: !_busy,
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onTap: _busy ? null : _export,
        ),
      ],
    );
  }
}

// ── About tile ─────────────────────────────────────────────────────────────────

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.info_outline_rounded, color: cs.onSurfaceVariant),
      title: const Text('Synology Notes Enhanced'),
      subtitle: const Text('Version 1.0.0'),
    );
  }
}
