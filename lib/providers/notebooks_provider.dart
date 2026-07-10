import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notebook.dart';
import 'app_mode_provider.dart';

final notebooksProvider = FutureProvider<List<Notebook>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listNotebooks();
});

final selectedNotebookIdProvider = StateProvider<String?>((ref) => null);

final selectedNotebookProvider = Provider<Notebook?>((ref) {
  final id = ref.watch(selectedNotebookIdProvider);
  if (id == null) return null;
  final notebooks = ref.watch(notebooksProvider).valueOrNull ?? [];
  return notebooks.where((n) => n.id == id).firstOrNull;
});
