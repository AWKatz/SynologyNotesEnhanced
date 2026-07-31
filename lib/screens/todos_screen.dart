import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/todo.dart';
import '../providers/api_provider.dart';
import '../providers/app_mode_provider.dart' show repositoryProvider;
import '../providers/todos_provider.dart';
import '../widgets/common/app_toast.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.createTodo(title: title);
      _controller.clear();
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _controller,
        enabled: !_busy,
        decoration: InputDecoration(
          hintText: 'Add a task…',
          isDense: true,
          prefixIcon: const Icon(Icons.add_rounded, size: 20),
          suffixIcon: _busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
        onSubmitted: (_) => _submit(),
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

  Future<void> _toggle({bool? done, bool? star}) async {
    final repo = ref.read(repositoryProvider);
    if (repo == null) return;
    try {
      await repo.updateTodo(todoId: widget.todo.id, done: done, star: star);
      syncTodosAfterMutation(ref);
    } catch (e) {
      debugPrint('Update todo failed: $e');
    }
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
            onChanged: isNas ? (v) => _toggle(done: v ?? false) : null,
          ),
          title: Text(
            todo.title,
            style: TextStyle(
              decoration: todo.done ? TextDecoration.lineThrough : null,
              color: todo.done ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
          subtitle: todo.dueDate == null && todo.comment.isEmpty
              ? null
              : Text(
                  [
                    if (todo.dueDate != null)
                      DateFormat.yMMMd().format(todo.dueDate!),
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
              IconButton(
                icon: Icon(
                  todo.star ? Icons.star_rounded : Icons.star_border_rounded,
                  color:
                      todo.star ? const Color(0xFFF59E0B) : cs.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: isNas ? () => _toggle(star: !todo.star) : null,
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
