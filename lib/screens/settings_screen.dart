import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/services/file_station_service.dart';
import '../core/services/nsx_service.dart';
import '../models/file_station_entry.dart';
import '../widgets/common/app_toast.dart';
import '../providers/api_provider.dart';
import '../providers/session_provider.dart';
import '../providers/app_mode_provider.dart';
import '../providers/notebooks_provider.dart';
import '../providers/shelves_provider.dart';
import '../providers/tags_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/reminder_settings_provider.dart';
import '../providers/stats_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todos_provider.dart';
import '../theme/app_theme.dart';

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
          _SectionHeader('Appearance'),
          const _AppearanceSection(),
          const Divider(height: 32, indent: 20, endIndent: 20),
          _SectionHeader('Reminders'),
          const _RemindersSection(),
          const Divider(height: 32, indent: 20, endIndent: 20),
          _SectionHeader('Library'),
          const _StatsGrid(),
          const _ResyncButton(),
          const Divider(height: 32, indent: 20, endIndent: 20),
          _SectionHeader('Storage Mode'),
          _ModeSelector(currentMode: mode),
          const Divider(height: 32, indent: 20, endIndent: 20),
          if (mode == AppMode.nas || mode == null) ...[
            _SectionHeader('Synology NAS'),
            _NasConnectionTile(session: session),
            const Divider(height: 32, indent: 20, endIndent: 20),
          ],
          _SectionHeader('Import / Export'),
          const _NsxImportExport(),
          if (mode == AppMode.nas) ...[
            const Divider(height: 32, indent: 20, endIndent: 20),
            _SectionHeader('NAS Export / Import (server-side)'),
            const _NasNsxJobSection(),
          ],
          const Divider(height: 32, indent: 20, endIndent: 20),
          _SectionHeader('About'),
          const _AboutTile(),
          const _GetSupportTile(),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
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
    ref.invalidate(todosProvider);
    ref.invalidate(selectedNoteIdProvider);
    ref.invalidate(selectedNotebookIdProvider);
  }
}

// ── Appearance ──────────────────────────────────────────────────────────────────

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final mode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider) ?? AppTheme.defaultSeed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, 48),
                textStyle: const TextStyle(fontSize: 14),
              ),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_rounded),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_rounded),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_rounded),
                  label: Text('Dark'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).setMode(selection.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text('Accent color',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: AppTheme.accentPalette.map((color) {
              final selected = color.toARGB32() == accent.toARGB32();
              // Preview the actual resulting primary + secondaryContainer
              // colors for this mode, not the raw seed — Material's tonal
              // algorithm (and the grey-specific monochrome path) can shift
              // these noticeably, and `vibrant` can spread them further
              // apart than the seed alone suggests. A two-way split shows
              // what buttons and tags will really look like rather than
              // risking a surprise once picked.
              final (previewPrimary, previewSecondaryContainer) =
                  AppTheme.previewSchemeFor(
                      color, Theme.of(context).brightness);
              final checkColor = previewPrimary.computeLuminance() > 0.5
                  ? Colors.black
                  : Colors.white;
              return InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () =>
                    ref.read(accentColorProvider.notifier).setColor(color),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(color: cs.onSurface, width: 2.5)
                        : null,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipOval(
                        child: Row(
                          // Row doesn't stretch children to fill its cross
                          // axis by default, and ColoredBox has no intrinsic
                          // size of its own — without this, each band (and
                          // the Row itself) collapses to zero height and the
                          // whole swatch disappears.
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: ColoredBox(color: previewPrimary)),
                            Expanded(
                                child: ColoredBox(
                                    color: previewSecondaryContainer)),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_rounded, color: checkColor, size: 22),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Reminders ───────────────────────────────────────────────────────────────────

/// A single app-wide time of day at which any to-do due that day gets a
/// local notification — see reminder_settings_provider.dart's doc comment
/// for why this isn't a per-todo time (NoteStation due dates are date-only,
/// with no time-of-day field to sync one against).
class _RemindersSection extends ConsumerWidget {
  const _RemindersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(remindersEnabledProvider);
    final time = ref.watch(reminderTimeProvider);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Due-date reminders'),
          subtitle: const Text(
              'Get notified about to-do items due that day, at the time below'),
          value: enabled,
          onChanged: (v) =>
              ref.read(remindersEnabledProvider.notifier).setEnabled(v),
        ),
        ListTile(
          enabled: enabled,
          leading: const Icon(Icons.schedule_rounded),
          title: const Text('Reminder time'),
          trailing: Text(time.format(context)),
          onTap: () async {
            final picked =
                await showTimePicker(context: context, initialTime: time);
            if (picked != null) {
              await ref.read(reminderTimeProvider.notifier).setTime(picked);
            }
          },
        ),
      ],
    );
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
        subtitle: Text(
          session.baseUrl,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
    final starred =
        totalNotes == null ? null : ref.watch(starredNotesCountProvider);
    final todos = ref.watch(todosCountProvider);
    final userNotebooks = notebooksAsync.valueOrNull == null
        ? null
        : ref.watch(userNotebooksCountProvider);
    final sharedNotebooks = notebooksAsync.valueOrNull == null
        ? null
        : ref.watch(sharedNotebooksCountProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final tagsCount =
        tagsAsync.valueOrNull == null ? null : ref.watch(tagsCountProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              _StatCell(label: 'Notes', value: totalNotes),
              _StatCell(label: 'Starred', value: starred),
              _StatCell(label: 'To-Do Lists', value: todos, isStub: true),
            ],
          ),
          const SizedBox(height: 12),
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
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        constraints: const BoxConstraints(minHeight: 88),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            isStub
                ? Text(
                    '–',
                    style: tt.headlineSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : value == null
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : Text(
                        '$value',
                        style: tt.headlineSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.sync_rounded),
          label: Text(isNas ? 'Re-sync with NAS' : 'Refresh Local Data'),
          onPressed: () {
            ref.invalidate(notebooksProvider);
            ref.invalidate(shelvesProvider);
            ref.invalidate(notesProvider);
            ref.invalidate(tagsProvider);
            ref.invalidate(todosProvider);
            ref.invalidate(selectedNoteIdProvider);
            ref.invalidate(selectedNotebookIdProvider);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    isNas ? 'Syncing with NAS…' : 'Refreshing local data…'),
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
      _snack(
          'Imported $notes note(s) and $nb notebook(s) into offline storage.');
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
    ref.invalidate(todosProvider);
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

// ── NAS-side (server) .nsx export/import job ────────────────────────────────
//
// Distinct from _NsxImportExport above (which parses/builds the .nsx ZIP
// format directly, client-side, via NsxCodec/NsxService). This triggers the
// real NAS's own async export/import job — SYNO.NoteStation.Export.Notebook/
// Import.Notebook — which writes/reads a .nsx file to/from a folder ON THE
// NAS ITSELF (see NoteStationService's matching doc comment). FileStation
// (SYNO.FileStation.*, see file_station_service.dart) closes the two gaps
// that used to leave this as free-text NAS-path fields: a real folder/file
// browser instead of typing a path by hand, and actually moving the
// resulting file to/from this device (upload a local .nsx before import,
// download an exported one after).

enum _BrowseMode { chooseFolder, chooseFile }

/// Breadcrumb NAS folder/file browser backed by SYNO.FileStation.List. In
/// [_BrowseMode.chooseFolder], only subfolders are listed and "Select this
/// folder" confirms wherever the user has navigated to; in
/// [_BrowseMode.chooseFile], files matching [namePattern] are also listed
/// and tapping one selects it directly (no separate confirm step).
class _FileStationBrowserDialog extends StatefulWidget {
  final FileStationService service;
  final _BrowseMode mode;
  final String? namePattern;
  final String? initialPath;

  const _FileStationBrowserDialog({
    required this.service,
    required this.mode,
    this.namePattern,
    this.initialPath,
  });

  @override
  State<_FileStationBrowserDialog> createState() =>
      _FileStationBrowserDialogState();
}

class _FileStationBrowserDialogState
    extends State<_FileStationBrowserDialog> {
  // null = at the root (shares list); otherwise the current folder's path.
  String? _currentPath;
  // Display labels for the path segments visited so far, for the breadcrumb
  // bar and "Up" navigation — kept separately from _currentPath's own
  // slash-splitting since a share's own display name isn't always its last
  // path segment.
  List<String> _breadcrumbs = const [];
  Future<List<FileStationEntry>>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath != null) {
      _currentPath = widget.initialPath;
      _breadcrumbs = [widget.initialPath!];
    }
    _load();
  }

  void _load() {
    setState(() {
      _future = _currentPath == null
          ? widget.service.listShares()
          : widget.service.listFolder(
              _currentPath!,
              directoriesOnly: widget.mode == _BrowseMode.chooseFolder,
              namePattern: widget.namePattern,
            );
    });
  }

  void _open(FileStationEntry entry) {
    if (entry.isDirectory) {
      setState(() {
        _currentPath = entry.path;
        _breadcrumbs = [..._breadcrumbs, entry.name];
      });
      _load();
    } else if (widget.mode == _BrowseMode.chooseFile) {
      Navigator.of(context).pop(entry.path);
    }
  }

  void _goUp() {
    if (_breadcrumbs.isEmpty) return;
    setState(() {
      _breadcrumbs = _breadcrumbs.sublist(0, _breadcrumbs.length - 1);
      if (_breadcrumbs.isEmpty) {
        _currentPath = null;
      } else {
        final segments = _currentPath!.split('/');
        _currentPath = segments.sublist(0, segments.length - 1).join('/');
      }
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.mode == _BrowseMode.chooseFolder
          ? 'Choose a folder'
          : 'Choose a file'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_breadcrumbs.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: 'Up',
                    onPressed: _goUp,
                  ),
                Expanded(
                  child: Text(
                    _currentPath ?? 'Shared folders',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<FileStationEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not list this folder:\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.error, fontSize: 12),
                        ),
                      ),
                    );
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return const Center(child: Text('Empty'));
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(entry.isDirectory
                            ? Icons.folder_rounded
                            : Icons.insert_drive_file_outlined),
                        title: Text(entry.name),
                        onTap: () => _open(entry),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.mode == _BrowseMode.chooseFolder)
          FilledButton(
            onPressed: _currentPath == null
                ? null
                : () => Navigator.of(context).pop(_currentPath),
            child: const Text('Select this folder'),
          ),
      ],
    );
  }
}

class _NasNsxJobSection extends ConsumerStatefulWidget {
  const _NasNsxJobSection();

  @override
  ConsumerState<_NasNsxJobSection> createState() => _NasNsxJobSectionState();
}

class _NasNsxJobSectionState extends ConsumerState<_NasNsxJobSection> {
  final _destController = TextEditingController(text: '/Downloads');
  final _importPathController = TextEditingController();
  bool _exporting = false;
  bool _importing = false;
  bool _transferring = false;
  String? _exportStatus;
  String? _importStatus;
  // Set once an export job finishes — lets "Download to this device" jump
  // straight to the folder the export just wrote into.
  String? _lastExportDest;

  @override
  void dispose() {
    _destController.dispose();
    _importPathController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _startExport() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    final dest = _destController.text.trim();
    if (dest.isEmpty) return;

    setState(() {
      _exporting = true;
      _exportStatus = 'Starting…';
    });
    try {
      await repo.startNotebookExport(destPath: dest);
      while (mounted) {
        await Future.delayed(const Duration(milliseconds: 1200));
        final status = await repo.getNotebookExportStatus();
        if (!mounted) return;
        setState(() =>
            _exportStatus = 'Exporting… ${status.current}/${status.total}');
        if (status.finished) break;
      }
      if (mounted) {
        _snack('Export finished — check $dest on the NAS.');
        setState(() => _lastExportDest = dest);
      }
    } catch (e) {
      debugPrint('NAS export failed: $e');
      if (mounted) _snack('Export failed.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _browseForExportFolder() async {
    final service = ref.read(fileStationServiceProvider);
    if (service == null) return;
    final path = await showDialog<String>(
      context: context,
      builder: (_) => _FileStationBrowserDialog(
        service: service,
        mode: _BrowseMode.chooseFolder,
      ),
    );
    if (path != null) setState(() => _destController.text = path);
  }

  Future<void> _browseForImportFile() async {
    final service = ref.read(fileStationServiceProvider);
    if (service == null) return;
    final path = await showDialog<String>(
      context: context,
      builder: (_) => _FileStationBrowserDialog(
        service: service,
        mode: _BrowseMode.chooseFile,
        namePattern: '*.nsx',
      ),
    );
    if (path != null) setState(() => _importPathController.text = path);
  }

  /// Pushes a local `.nsx` (e.g. one made via this app's own offline
  /// NsxCodec export) onto the NAS, then fills in the import path field
  /// with wherever it landed — closes the "moving that file to/from this
  /// device" gap the import job otherwise leaves (it only ever reads a
  /// file already on the NAS).
  Future<void> _uploadFromDevice() async {
    final service = ref.read(fileStationServiceProvider);
    if (service == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['nsx'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;
    if (!mounted) return;

    final folder = await showDialog<String>(
      context: context,
      builder: (_) => _FileStationBrowserDialog(
        service: service,
        mode: _BrowseMode.chooseFolder,
      ),
    );
    if (folder == null) return;

    setState(() => _transferring = true);
    try {
      await service.uploadFile(
        remoteFolderPath: folder,
        fileName: file.name,
        bytes: file.bytes!,
      );
      if (mounted) {
        setState(() => _importPathController.text = '$folder/${file.name}');
        _snack('Uploaded ${file.name} to $folder on the NAS.');
      }
    } catch (e) {
      if (mounted) _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  /// Lets the user pick the just-exported `.nsx` on the NAS (starting in
  /// the folder the export wrote into, if known) and download it here —
  /// closes the other half of the "move to/from this device" gap.
  Future<void> _downloadExportedFile() async {
    final service = ref.read(fileStationServiceProvider);
    if (service == null) return;
    final nasPath = await showDialog<String>(
      context: context,
      builder: (_) => _FileStationBrowserDialog(
        service: service,
        mode: _BrowseMode.chooseFile,
        namePattern: '*.nsx',
        initialPath: _lastExportDest,
      ),
    );
    if (nasPath == null) return;

    setState(() => _transferring = true);
    try {
      final bytes = Uint8List.fromList(await service.downloadFile(path: nasPath));
      if (!mounted) return;
      final localPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save exported .nsx',
        fileName: nasPath.split('/').last,
        type: FileType.custom,
        allowedExtensions: ['nsx'],
        bytes: bytes,
      );
      if (localPath == null) return; // cancelled
      // On desktop saveFile returns a path but doesn't write; write here —
      // mirrors _NsxImportExportState._export's own comment/pattern above.
      final f = File(localPath);
      if (!f.existsSync() || f.lengthSync() == 0) {
        f.writeAsBytesSync(bytes);
      }
      if (mounted) _snack('Downloaded to $localPath');
    } catch (e) {
      if (mounted) _snack('Download failed: $e');
    } finally {
      if (mounted) setState(() => _transferring = false);
    }
  }

  Future<void> _startImport() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    final path = _importPathController.text.trim();
    if (path.isEmpty) return;
    final fileName = path.split('/').last;

    setState(() {
      _importing = true;
      _importStatus = 'Starting…';
    });
    try {
      await repo.startNotebookImport(fileName: fileName, nasPath: path);
      while (mounted) {
        await Future.delayed(const Duration(milliseconds: 1200));
        final status = await repo.getNotebookImportStatus();
        if (!mounted) return;
        setState(() =>
            _importStatus = 'Importing… ${status.current}/${status.total}');
        if (status.finished) break;
      }
      if (mounted) {
        _snack('Import finished.');
        syncAfterMutation(ref);
      }
    } catch (e) {
      debugPrint('NAS import failed: $e');
      if (mounted) _snack('Import failed.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exports/imports a .nsx file on the NAS itself — browse to a '
            'folder, or upload/download the file to move it to or from this '
            'device.',
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _destController,
            enabled: !_exporting,
            decoration: InputDecoration(
              labelText: 'Export destination folder (NAS path)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open_rounded),
                tooltip: 'Browse NAS folders',
                onPressed: _exporting ? null : _browseForExportFolder,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _exporting ? null : _startExport,
                child: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Start NAS export'),
              ),
              if (_lastExportDest != null)
                OutlinedButton(
                  onPressed: _transferring ? null : _downloadExportedFile,
                  child: const Text('Download to this device'),
                ),
              if (_exportStatus != null)
                Text(_exportStatus!, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _importPathController,
            enabled: !_importing,
            decoration: InputDecoration(
              labelText: 'Import file path (NAS path, e.g. /Downloads/x.nsx)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open_rounded),
                tooltip: 'Browse NAS files',
                onPressed: _importing ? null : _browseForImportFile,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _importing ? null : _startImport,
                child: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Start NAS import'),
              ),
              OutlinedButton(
                onPressed: _transferring ? null : _uploadFromDevice,
                child: const Text('Upload from this device…'),
              ),
              if (_importStatus != null)
                Text(_importStatus!, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
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
      // Reads the version pubspec.yaml declares rather than a hardcoded
      // copy — that field is the single source of truth we actually bump
      // per release, and a second hand-maintained copy here is exactly how
      // this drifted out of sync (pubspec at 1.0.0, this stuck on 1.0.0 too
      // until the pubspec moved and this didn't).
      subtitle: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.data?.version;
          return Text(version == null ? 'Version…' : 'Version $version');
        },
      ),
    );
  }
}

class _GetSupportTile extends StatelessWidget {
  const _GetSupportTile();

  static final _supportUri = Uri(
    scheme: 'mailto',
    path: 'aaron@simpleflights.ca',
    queryParameters: {'subject': 'Synology Notes Enhanced - Support Request'},
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.support_agent_rounded, color: cs.onSurfaceVariant),
      title: const Text('Get Support'),
      subtitle: const Text('Email the developer'),
      onTap: () => _emailSupport(context),
    );
  }

  Future<void> _emailSupport(BuildContext context) async {
    try {
      final launched =
          await launchUrl(_supportUri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        AppToast.error(context, 'Could not open your email app.');
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, 'Could not open your email app.');
      }
    }
  }
}
