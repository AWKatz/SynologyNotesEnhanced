import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/todo.dart';
import 'app_mode_provider.dart';

final todosProvider = FutureProvider<List<Todo>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listTodos();
});

enum TodoFilter { all, active, done, starred }

final todoFilterProvider = StateProvider<TodoFilter>((ref) => TodoFilter.all);

final filteredTodosProvider = Provider<List<Todo>>((ref) {
  final todos = ref.watch(todosProvider).valueOrNull ?? [];
  final filter = ref.watch(todoFilterProvider);
  final filtered = switch (filter) {
    TodoFilter.all => todos,
    TodoFilter.active => todos.where((t) => !t.done).toList(),
    TodoFilter.done => todos.where((t) => t.done).toList(),
    TodoFilter.starred => todos.where((t) => t.star).toList(),
  };
  // Starred first, then by due date (soonest first, no-due-date last), then title.
  filtered.sort((a, b) {
    if (a.star != b.star) return a.star ? -1 : 1;
    if (a.dueDate == null && b.dueDate == null) {
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  });
  return filtered;
});

/// Mirrors syncAfterMutation in notes_provider.dart, scoped to Todo state.
void syncTodosAfterMutation(WidgetRef ref) {
  ref.invalidate(todosProvider);
}
