import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyRemindersEnabled = 'reminders_enabled';
const _keyReminderMinutesSinceMidnight = 'reminders_time_of_day_minutes';

const defaultReminderTime = TimeOfDay(hour: 9, minute: 0);

class RemindersEnabledNotifier extends StateNotifier<bool> {
  RemindersEnabledNotifier() : super(true) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_keyRemindersEnabled);
    if (saved != null) state = saved;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemindersEnabled, enabled);
  }
}

final remindersEnabledProvider =
    StateNotifierProvider<RemindersEnabledNotifier, bool>(
        (ref) => RemindersEnabledNotifier());

/// A single app-wide time of day at which any to-do due that day gets a
/// local reminder notification — NoteStation due dates are date-only (never
/// synced with a time-of-day), so this stays a local-only setting rather
/// than a per-todo field with nowhere to live server-side.
class ReminderTimeNotifier extends StateNotifier<TimeOfDay> {
  ReminderTimeNotifier() : super(defaultReminderTime) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt(_keyReminderMinutesSinceMidnight);
    if (minutes != null) {
      state = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    }
  }

  Future<void> setTime(TimeOfDay time) async {
    state = time;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        _keyReminderMinutesSinceMidnight, time.hour * 60 + time.minute);
  }
}

final reminderTimeProvider =
    StateNotifierProvider<ReminderTimeNotifier, TimeOfDay>(
        (ref) => ReminderTimeNotifier());
