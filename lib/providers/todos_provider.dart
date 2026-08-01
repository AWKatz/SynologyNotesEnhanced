import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/todo.dart';
import 'app_mode_provider.dart';

final todosProvider = FutureProvider<List<Todo>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return [];
  return repo.listTodos();
});

enum TodoFilter { all, active, done, starred, dueToday, dueWithin7Days }

final todoFilterProvider = StateProvider<TodoFilter>((ref) => TodoFilter.all);

/// Due today or overdue, and not yet done — mirrors DS Note's own "Today"
/// smart view (client-side only; there is no server-side due-date filter
/// captured for Todo.list, so this always fetches everything and narrows
/// here, same as every other Todo/note filter in this app).
bool isDueToday(Todo t) {
  if (t.dueDate == null || t.done) return false;
  final today = _dateOnly(DateTime.now());
  return !_dateOnly(t.dueDate!).isAfter(today);
}

/// Due within the next 7 days (inclusive of today) or overdue, and not yet
/// done — a superset of [isDueToday], mirroring DS Note's "Next 7 days" view.
bool isDueWithin7Days(Todo t) {
  if (t.dueDate == null || t.done) return false;
  final today = _dateOnly(DateTime.now());
  final horizon = today.add(const Duration(days: 7));
  return !_dateOnly(t.dueDate!).isAfter(horizon);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Sidebar badge counts — independent of whatever filter TodosScreen itself
/// currently has selected.
final dueTodayCountProvider = Provider<int>((ref) {
  final todos = ref.watch(todosProvider).valueOrNull ?? [];
  return todos.where(isDueToday).length;
});

final dueWithin7DaysCountProvider = Provider<int>((ref) {
  final todos = ref.watch(todosProvider).valueOrNull ?? [];
  return todos.where(isDueWithin7Days).length;
});

final filteredTodosProvider = Provider<List<Todo>>((ref) {
  final todos = ref.watch(todosProvider).valueOrNull ?? [];
  final filter = ref.watch(todoFilterProvider);
  final filtered = switch (filter) {
    TodoFilter.all => todos,
    TodoFilter.active => todos.where((t) => !t.done).toList(),
    TodoFilter.done => todos.where((t) => t.done).toList(),
    TodoFilter.starred => todos.where((t) => t.star).toList(),
    TodoFilter.dueToday => todos.where(isDueToday).toList(),
    TodoFilter.dueWithin7Days => todos.where(isDueWithin7Days).toList(),
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
