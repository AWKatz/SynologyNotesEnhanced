import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/todo.dart';
import '../providers/api_provider.dart';
import '../providers/app_mode_provider.dart' show repositoryProvider;
import '../providers/todos_provider.dart';
import '../widgets/common/app_toast.dart';

/// UNVERIFIED bucket mapping — the only capture evidence is a single
/// `Todo.set(priority: 300)` call (`.docs/reference/To Do list capture*.har`);
/// no low/medium value has ever been captured. These four levels are an
/// inferred even spread with 300 anchored at that one confirmed data point.
/// If the real Note Station client shows a different level for these numbers
/// (e.g. 300 turns out to be "Medium", not "High"), fix the map below rather
/// than guess again — ideally after capturing the other levels.
enum TodoPriority { none, low, medium, high }

const _priorityValues = {
  TodoPriority.none: -1,
  TodoPriority.low: 100,
  TodoPriority.medium: 200,
  TodoPriority.high: 300,
};

TodoPriority _priorityFromValue(int v) {
  if (v >= 300) return TodoPriority.high;
  if (v >= 200) return TodoPriority.medium;
  if (v >= 100) return TodoPriority.low;
  return TodoPriority.none;
}

const _priorityColors = {
  TodoPriority.none: null,
  TodoPriority.low: Color(0xFF4CAF50),
  TodoPriority.medium: Color(0xFFF59E0B),
  TodoPriority.high: Color(0xFFEF4444),
};

const _priorityLabels = {
  TodoPriority.none: 'None',
  TodoPriority.low: 'Low',
  TodoPriority.medium: 'Medium',
  TodoPriority.high: 'High',
};

class TodosScreen extends ConsumerWidget {
  const TodosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isNas = ref.watch(noteStationServiceProvider) != null;
    final todosAsync = ref.watch(todosProvider);
    final filter = ref.watch(todoFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('To-Do'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      backgroundColor: cs.surface,
      body: Column(
        children: [
          if (!isNas)
            Container(
              width: double.infinity,
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'To-Do requires an active NAS connection.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in TodoFilter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      TodoFilter.all => 'All',
                      TodoFilter.active => 'Active',
                      TodoFilter.done => 'Done',
                      TodoFilter.starred => 'Starred',
                      TodoFilter.dueToday => 'Due Today',
                      TodoFilter.dueWithin7Days => 'Next 7 Days',
                    }),
                    selected: filter == f,
                    onSelected: (_) =>
                        ref.read(todoFilterProvider.notifier).state = f,
                  ),
              ],
            ),
          ),
          if (isNas) _NewTaskField(),
          const Divider(height: 1),
          Expanded(
            child: todosAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              error: (e, _) => Center(
                child: Text('Failed to load to-dos',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
              data: (_) {
                final todos = ref.watch(filteredTodosProvider);
                if (todos.isEmpty) {
                  return Center(
                    child: Text('No to-dos here',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  );
                }
                return ListView.builder(
                  itemCount: todos.length,
                  itemBuilder: (context, i) => _TodoTile(todo: todos[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NewTaskField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewTaskField> createState() => _NewTaskFieldState();
}

class _NewTaskFieldState extends ConsumerState<_NewTaskField> {
  final _controller = TextEditingController();
  bool _busy = false;
  DateTime? _dueDate;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      // VERIFIED (To Do list capture*.har): due_date is only ever confirmed
      // set at CREATE time, not as a later edit — this is the one place a
      // due date is set from scratch rather than via updateTodo.
      await repo.createTodo(title: title, dueDate: _dueDate);
      _controller.clear();
      setState(() => _dueDate = null);
      syncTodosAfterMutation(ref);
    } catch (e) {
      debugPrint('Create todo failed: $e');
      if (mounted) AppToast.error(context, 'Could not add the task.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            enabled: !_busy,
            decoration: InputDecoration(
              hintText: 'Add a task…',
              isDense: true,
              prefixIcon: const Icon(Icons.add_rounded, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.calendar_today_rounded,
                        size: 18,
                        color: _dueDate != null ? cs.primary : null),
                    tooltip: 'Due date',
                    onPressed: _busy ? null : _pickDueDate,
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_dueDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InputChip(
                label: Text(DateFormat.yMMMd().format(_dueDate!)),
                avatar: const Icon(Icons.calendar_today_rounded, size: 14),
                onDeleted: () => setState(() => _dueDate = null),
              ),
            ),
        ],
      ),
    );
  }
}

/// A parent task tile, optionally expandable to show/add subtasks.
/// VERIFIED (`.docs/reference/Substasks*.har`): a parent's own `items` field
/// is an array of subtask object_id strings (not nested objects) — subtask
/// details are fetched separately via listTodos(parentId: parent.id), and
/// created via createTodo(title:, parentId: parent.id).
class _TodoTile extends ConsumerStatefulWidget {
  final Todo todo;
  const _TodoTile({required this.todo});

  @override
  ConsumerState<_TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends ConsumerState<_TodoTile> {
  bool _expanded = false;

  Future<void> _update({
    bool? done,
    bool? star,
    int? priority,
    DateTime? dueDate,
  }) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      await repo.updateTodo(
        todoId: widget.todo.id,
        done: done,
        star: star,
        priority: priority,
        dueDate: dueDate,
      );
      syncTodosAfterMutation(ref);
    } catch (e) {
      debugPrint('Update todo failed: $e');
    }
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.todo.dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) _update(dueDate: picked);
  }

  Future<void> _delete() async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      await repo.deleteTodo(widget.todo.id);
      syncTodosAfterMutation(ref);
    } catch (e) {
      debugPrint('Delete todo failed: $e');
      if (mounted) AppToast.error(context, 'Could not delete the task.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNas = ref.watch(noteStationServiceProvider) != null;
    final todo = widget.todo;
    final hasSubtasks = todo.subtaskIds.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Checkbox(
            value: todo.done,
            onChanged: isNas ? (v) => _update(done: v ?? false) : null,
          ),
          title: Text(
            todo.title,
            style: TextStyle(
              decoration: todo.done ? TextDecoration.lineThrough : null,
              color: todo.done ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
          subtitle: todo.dueDate == null &&
                  todo.comment.isEmpty &&
                  _priorityFromValue(todo.priority) == TodoPriority.none
              ? null
              : Text(
                  [
                    if (todo.dueDate != null)
                      DateFormat.yMMMd().format(todo.dueDate!),
                    if (_priorityFromValue(todo.priority) != TodoPriority.none)
                      '${_priorityLabels[_priorityFromValue(todo.priority)]} priority',
                    if (todo.comment.isNotEmpty) todo.comment,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSubtasks || isNas)
                IconButton(
                  icon: Icon(
                    hasSubtasks
                        ? (_expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded)
                        : Icons.playlist_add_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: hasSubtasks ? 'Subtasks' : 'Add subtask',
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              if (isNas)
                PopupMenuButton<TodoPriority>(
                  tooltip: 'Priority',
                  icon: Icon(
                    Icons.flag_rounded,
                    size: 20,
                    color: _priorityColors[_priorityFromValue(todo.priority)] ??
                        cs.onSurfaceVariant,
                  ),
                  onSelected: (p) => _update(priority: _priorityValues[p]),
                  itemBuilder: (context) => TodoPriority.values
                      .map((p) => PopupMenuItem(
                            value: p,
                            child: Row(
                              children: [
                                if (_priorityColors[p] != null)
                                  Icon(Icons.flag_rounded,
                                      size: 16, color: _priorityColors[p])
                                else
                                  const SizedBox(width: 16),
                                const SizedBox(width: 8),
                                Text(_priorityLabels[p]!),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              if (isNas)
                IconButton(
                  icon: Icon(Icons.calendar_today_rounded,
                      size: 18,
                      color: todo.dueDate != null ? cs.primary : cs.onSurfaceVariant),
                  tooltip: 'Due date',
                  onPressed: _pickDueDate,
                ),
              IconButton(
                icon: Icon(
                  todo.star ? Icons.star_rounded : Icons.star_border_rounded,
                  color:
                      todo.star ? const Color(0xFFF59E0B) : cs.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: isNas ? () => _update(star: !todo.star) : null,
              ),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: cs.onSurfaceVariant),
                onPressed: isNas ? _delete : null,
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 40, right: 16, bottom: 8),
            child: _SubtaskList(parent: todo),
          ),
      ],
    );
  }
}

class _SubtaskList extends ConsumerStatefulWidget {
  final Todo parent;
  const _SubtaskList({required this.parent});

  @override
  ConsumerState<_SubtaskList> createState() => _SubtaskListState();
}

class _SubtaskListState extends ConsumerState<_SubtaskList> {
  late Future<List<Todo>> _future;
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(repositoryProvider);
    _future = repo == null
        ? Future.value(const [])
        : repo.listTodos(parentId: widget.parent.id);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addSubtask() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _adding = true);
    try {
      await repo.createTodo(title: title, parentId: widget.parent.id);
      _controller.clear();
      syncTodosAfterMutation(ref);
      setState(_load);
    } catch (e) {
      debugPrint('Create subtask failed: $e');
      if (mounted) AppToast.error(context, 'Could not add the subtask.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggleSubtask(Todo sub, bool done) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      await repo.updateTodo(todoId: sub.id, done: done);
      syncTodosAfterMutation(ref);
      setState(_load);
    } catch (e) {
      debugPrint('Update subtask failed: $e');
    }
  }

  Future<void> _deleteSubtask(Todo sub) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      await repo.deleteTodo(sub.id);
      syncTodosAfterMutation(ref);
      setState(_load);
    } catch (e) {
      debugPrint('Delete subtask failed: $e');
      if (mounted) AppToast.error(context, 'Could not delete the subtask.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Todo>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final subtasks = snapshot.data!;
            if (subtasks.isEmpty) return const SizedBox.shrink();
            return Column(
              children: subtasks
                  .map((sub) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: Checkbox(
                                value: sub.done,
                                onChanged: (v) =>
                                    _toggleSubtask(sub, v ?? false),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                sub.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  decoration: sub.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: sub.done
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded,
                                  size: 16, color: cs.onSurfaceVariant),
                              onPressed: () => _deleteSubtask(sub),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            );
          },
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_adding,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Add subtask…',
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _addSubtask(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: _adding ? null : _addSubtask,
            ),
          ],
        ),
      ],
    );
  }
}
