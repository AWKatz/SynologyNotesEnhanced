import 'package:flutter_test/flutter_test.dart';
import 'package:synologynotesenhanceds_enhanced/models/todo.dart';
import 'package:synologynotesenhanceds_enhanced/providers/todos_provider.dart';

/// isDueToday/isDueWithin7Days back the sidebar's "Due Today"/"Next 7 Days"
/// nav shortcuts (mirroring DS Note's own To-do smart views) — client-side
/// only, since there's no server-side due-date filter captured for
/// Todo.list. Pins the date-boundary math (today, overdue, exactly-7-days,
/// 8-days-out, done tasks excluded, no-due-date excluded).
void main() {
  Todo todoWithDueDate(DateTime? due, {bool done = false}) => Todo(
        id: 'T1',
        title: 'x',
        dueDate: due,
        done: done,
      );

  final now = DateTime.now();
  DateTime daysFromNow(int n) =>
      DateTime(now.year, now.month, now.day).add(Duration(days: n));

  group('isDueToday', () {
    test('true for a task due today', () {
      expect(isDueToday(todoWithDueDate(daysFromNow(0))), isTrue);
    });

    test('true for an overdue task (due yesterday)', () {
      expect(isDueToday(todoWithDueDate(daysFromNow(-1))), isTrue);
    });

    test('false for a task due tomorrow', () {
      expect(isDueToday(todoWithDueDate(daysFromNow(1))), isFalse);
    });

    test('false when done, even if due today', () {
      expect(isDueToday(todoWithDueDate(daysFromNow(0), done: true)), isFalse);
    });

    test('false when no due date set', () {
      expect(isDueToday(todoWithDueDate(null)), isFalse);
    });
  });

  group('isDueWithin7Days', () {
    test('true for a task due exactly 7 days out', () {
      expect(isDueWithin7Days(todoWithDueDate(daysFromNow(7))), isTrue);
    });

    test('false for a task due 8 days out', () {
      expect(isDueWithin7Days(todoWithDueDate(daysFromNow(8))), isFalse);
    });

    test('true for a task due today (superset of isDueToday)', () {
      expect(isDueWithin7Days(todoWithDueDate(daysFromNow(0))), isTrue);
    });

    test('true for an overdue task', () {
      expect(isDueWithin7Days(todoWithDueDate(daysFromNow(-3))), isTrue);
    });

    test('false when done', () {
      expect(
          isDueWithin7Days(todoWithDueDate(daysFromNow(2), done: true)),
          isFalse);
    });

    test('false when no due date set', () {
      expect(isDueWithin7Days(todoWithDueDate(null)), isFalse);
    });
  });
}
