import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which grid note_list.dart's folder strip shows (Folders/Tags/Smart) —
/// shared (not private to note_list.dart) so the sidebar's "Smart Notebooks"
/// nav shortcut can switch to Smart mode and land the user on it directly.
enum FolderStripMode { folders, tags, smart }

final folderStripModeProvider =
    StateProvider<FolderStripMode>((ref) => FolderStripMode.folders);

/// Purely a UI preference (not persisted) — lets a user reclaim the folder
/// strip's screen space for the note grid below it without losing the strip
/// entirely, via the strip header's own collapse toggle.
final folderStripCollapsedProvider = StateProvider<bool>((ref) => false);
