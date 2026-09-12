import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../models/todo.dart';

/// Schedules local due-date reminder notifications for to-do items and keeps
/// the app icon badge in sync with the due-today/overdue count.
///
/// NoteStation due dates are date-only — there's no synced time-of-day field
/// — so every reminder fires at one app-wide time (see
/// reminder_settings_provider.dart), not a per-todo time.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'todo_reminders';
  static const _channelName = 'To-do reminders';
  static const _channelDescription =
      'Reminders for to-do items with a due date';

  // Fixed id for the silent iOS/macOS badge-only "notification" (see
  // updateBadge) — reusing one id means each call replaces the last rather
  // than accumulating a new entry every time the badge changes.
  static const _badgeNotificationId = 0x5EED;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (e) {
      // Falls back to whatever timezone package's own local default is
      // (UTC) — reminders would then fire at the wrong wall-clock time
      // rather than not at all, so this is degraded, not broken.
      debugPrint(
          'NotificationService: could not resolve local timezone: $e');
    }

    const darwinSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: const WindowsInitializationSettings(
          appName: 'Synology Notes Enhanced',
          // Matches android/app/build.gradle.kts's applicationId — reused
          // here purely as a stable, already-unique identifier, not because
          // Windows cares about Android package names.
          appUserModelId: 'com.AWKatz.SynologyNotesEnhanced',
          // Fixed, arbitrary v4 GUID — Windows just needs any stable,
          // unique value to correlate notification-activation callbacks.
          guid: '5d5c5b1e-7f2a-4b3e-9c1a-9b6b9b6f9b6a',
        ),
      ),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
      // Lets the user grant exact-alarm scheduling via system settings on
      // Android 12+; without it, scheduled reminders silently degrade to
      // inexact timing rather than failing outright.
      await android.requestExactAlarmsPermission();
      await android.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
      ));
    }

    _initialized = true;
  }

  /// Deterministic from the todo's own id — no separate id-allocation state
  /// to keep in sync, at the (accepted, low) cost of a hash collision
  /// between two todos silently overwriting each other's reminder. Masked
  /// to a positive 31-bit int since Android's notification ids are int32.
  static int _notificationIdFor(String todoId) =>
      todoId.hashCode & 0x7fffffff;

  Future<void> scheduleTodoReminder(Todo todo, TimeOfDay time) async {
    if (!_initialized) return;
    final due = todo.dueDate;
    if (due == null) return;

    final scheduled = tz.TZDateTime(
        tz.local, due.year, due.month, due.day, time.hour, time.minute);
    // Never backfill a reminder whose time has already passed today (or an
    // overdue todo's past due date) — reconcileAll runs on every todo
    // mutation and app resume, so this would otherwise re-fire constantly.
    if (!scheduled.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _plugin.zonedSchedule(
      id: _notificationIdFor(todo.id),
      title: 'Due today: ${todo.title}',
      body: todo.comment.isNotEmpty ? todo.comment : null,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName,
            channelDescription: _channelDescription),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelTodoReminder(String todoId) =>
      _plugin.cancel(id: _notificationIdFor(todoId));

  /// Cancels every previously-scheduled reminder and reschedules fresh from
  /// [todos] — simpler and just as correct as diffing against a separately
  /// tracked "what's currently scheduled" set, and this only ever runs
  /// against a user's own todo list (dozens, not thousands), so the
  /// cancel-then-reschedule-everything cost is negligible. Also the only
  /// way to naturally pick up deletions without extra bookkeeping.
  Future<void> reconcileAll(
    List<Todo> todos, {
    required bool enabled,
    required TimeOfDay time,
  }) async {
    if (!_initialized) return;
    await _plugin.cancelAll();
    if (!enabled) return;
    for (final todo in todos) {
      if (todo.done || todo.dueDate == null) continue;
      await scheduleTodoReminder(todo, time);
    }
  }

  /// Updates the app icon badge to [count] (due-today + overdue todos).
  ///
  /// Only iOS/macOS get a real update here — this plugin exposes badge
  /// control solely via a notification's own presentation options, so a
  /// fully silent (no alert/banner/sound) "show" is used to set just the
  /// badge without anything visibly appearing. Android's badge is
  /// launcher-dependent and tied to active notification count rather than
  /// an arbitrary settable number, and Linux/Windows have no equivalent
  /// concept in this plugin, so this is a best-effort no-op there.
  Future<void> updateBadge(int count) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: _badgeNotificationId,
        notificationDetails: NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBanner: false,
            presentList: false,
            presentSound: false,
            presentBadge: true,
            badgeNumber: count,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBanner: false,
            presentList: false,
            presentSound: false,
            presentBadge: true,
            badgeNumber: count,
          ),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService: badge update failed: $e');
    }
  }
}
