import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/notes_repository.dart';
import '../repositories/nas_notes_repository.dart';
import '../repositories/local_notes_repository.dart';
import 'api_provider.dart';
import 'session_provider.dart';

enum AppMode { nas, local }

/// null = user hasn't chosen a mode yet (shows login screen).
final appModeProvider = StateProvider<AppMode?>((ref) => null);

/// Whether the sidebar (first column) is collapsed in the wide layout.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// true when the user has authenticated (NAS login or chosen local mode).
final isAuthenticatedProvider = Provider<bool>((ref) {
  final mode = ref.watch(appModeProvider);
  if (mode == null) return false;
  if (mode == AppMode.local) return true;
  return ref.watch(sessionProvider) != null;
});

final repositoryProvider = Provider<NotesRepository?>((ref) {
  final mode = ref.watch(appModeProvider);
  if (mode == null) return null;
  if (mode == AppMode.local) return LocalNotesRepository();
  final service = ref.watch(noteStationServiceProvider);
  if (service == null) return null;
  return NasNotesRepository(service);
});
