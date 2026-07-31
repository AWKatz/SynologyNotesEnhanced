import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/smart_notebook.dart';
import 'app_mode_provider.dart';

final smartNotebooksProvider = FutureProvider<List<SmartNotebook>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listSmartNotebooks();
});

final selectedSmartNotebookIdProvider = StateProvider<String?>((ref) => null);

final selectedSmartNotebookProvider = Provider<SmartNotebook?>((ref) {
  final id = ref.watch(selectedSmartNotebookIdProvider);
  if (id == null) return null;
  final list = ref.watch(smartNotebooksProvider).valueOrNull ?? [];
  return list.where((s) => s.id == id).firstOrNull;
});

/// Opening a smart notebook doesn't need its criteria remembered anymore —
/// see NoteStationService.listNotesInSmart's doc comment: the server
/// computes matches itself from `smart_id` alone, the same for a notebook
/// this app just created or one fetched back from a prior session.
Future<SmartNotebook> createSmartNotebook(
  WidgetRef ref, {
  required String title,
  required SmartCriteria criteria,
}) async {
  final repo = ref.read(repositoryProvider);
  if (repo == null) {
    throw StateError('Smart notebooks require an active repository.');
  }
  final created =
      await repo.createSmartNotebook(title: title, criteria: criteria);
  ref.invalidate(smartNotebooksProvider);
  return created;
}
