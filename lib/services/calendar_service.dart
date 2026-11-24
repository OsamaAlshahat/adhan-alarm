import 'dart:io';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import '../models/alarm_model.dart';
import 'location_service.dart';
import 'storage_service.dart';

/// Safely format calendar display name without ever showing "null"
String calendarDisplayName(dc.Calendar cal) {
  var name = (cal.name != null && cal.name!.trim().isNotEmpty && cal.name != 'null')
      ? cal.name!.trim()
      : null;
  final account = (cal.accountName != null && cal.accountName!.trim().isNotEmpty && cal.accountName != 'null')
      ? cal.accountName!.trim()
      : null;

  final isSamsung = cal.accountType?.toLowerCase().contains('samsung') == true ||
                    account?.toLowerCase().contains('samsung') == true ||
                    account?.toLowerCase() == 'phone' ||
                    account?.toLowerCase() == 'my phone';

  final isApple = cal.accountType?.toLowerCase().contains('apple') == true ||
                  cal.accountType?.toLowerCase().contains('icloud') == true ||
                  account?.toLowerCase().contains('icloud') == true ||
                  account?.toLowerCase().contains('apple') == true;

  if (name == null || name.isEmpty) {
    if (isSamsung) {
      name = 'Samsung Calendar';
    } else if (isApple) {
      name = 'Apple Calendar';
    } else if (cal.isDefault == true) {
      name = 'Phone Calendar';
    } else if (account != null && account.isNotEmpty) {
      name = account;
    } else {
      name = 'Calendar ${cal.id ?? ""}';
    }
  }

  if (isSamsung && (account?.toLowerCase() == 'phone' || account?.toLowerCase() == 'my phone')) {
    return '$name (Phone)';
  } else if (isApple && account != null && !name.toLowerCase().contains('icloud') && !name.toLowerCase().contains('apple')) {
    return '$name ($account)';
  } else if (account != null && name != account && !name.contains(account)) {
    return '$name ($account)';
  }
  return name;
}

// ===================================================================
// Calendar Service — best-effort sync, never blocks alarm scheduling
// ===================================================================
class CalendarService {
  static final _plugin = dc.DeviceCalendarPlugin();

  /// Request permissions for calendar read and write
  static Future<bool> requestPermissions() async {
    try {
      var isGranted = false;
      if (Platform.isIOS) {
        final res = await Permission.calendarFullAccess.request();
        isGranted = res.isGranted;
        if (!isGranted) {
          final resLegacy = await Permission.calendar.request();
          isGranted = resLegacy.isGranted;
        }
      } else {
        var status = await Permission.calendar.isGranted;
        if (!status) {
          final res = await Permission.calendar.request();
          isGranted = res.isGranted;
        } else {
          isGranted = true;
        }
      }
      var perms = await _plugin.hasPermissions();
      if (perms.isSuccess && perms.data == true) {
        isGranted = true;
      } else if (!isGranted) {
        final req = await _plugin.requestPermissions();
        if (req.isSuccess && req.data == true) {
          isGranted = true;
        }
      }
      return isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Get all device calendars (Samsung Calendar, Google Calendar, etc.)
  static Future<List<dc.Calendar>> getWritableCalendars() async {
    try {
      await requestPermissions();
      final result = await _plugin.retrieveCalendars();
      if (!result.isSuccess || result.data == null) return [];

      final all = result.data!;

      // 1. Filter out entries with invalid/null ID
      final valid = all.where((c) {
        final id = c.id?.trim();
        return id != null && id.isNotEmpty && id != 'null';
      }).toList();

      if (valid.isEmpty) return [];

      // 2. Deduplicate by unique calendar ID
      final seenIds = <String>{};
      final uniqueList = <dc.Calendar>[];
      for (final c in valid) {
        if (!seenIds.contains(c.id!)) {
          seenIds.add(c.id!);
          uniqueList.add(c);
        }
      }

      // 3. Put device default / primary calendar first (e.g. Samsung Calendar, Apple/iCloud Calendar)
      uniqueList.sort((a, b) {
        if (a.isDefault == true && b.isDefault != true) return -1;
        if (b.isDefault == true && a.isDefault != true) return 1;
        final aIsLocal = a.accountType?.toLowerCase().contains('samsung') == true ||
                         a.accountType?.toLowerCase().contains('icloud') == true ||
                         a.accountType?.toLowerCase().contains('apple') == true ||
                         a.accountName?.toLowerCase() == 'phone';
        final bIsLocal = b.accountType?.toLowerCase().contains('samsung') == true ||
                         b.accountType?.toLowerCase().contains('icloud') == true ||
                         b.accountType?.toLowerCase().contains('apple') == true ||
                         b.accountName?.toLowerCase() == 'phone';
        if (aIsLocal && !bIsLocal) return -1;
        if (bIsLocal && !aIsLocal) return 1;
        return 0;
      });

      return uniqueList;
    } catch (_) {
      return [];
    }
  }

  /// Get the effective calendar ID for an alarm
  static Future<String?> effectiveCalendarId(Al alarm) async {
    final id = alarm.calendarId ?? st.defaultCalendarId;
    if (id != null) {
      // Verify it still exists and is writable
      final cals = await getWritableCalendars();
      if (cals.any((c) => c.id == id)) return id;
    }
    // Fallback: first writable calendar
    final cals = await getWritableCalendars();
    return cals.isNotEmpty ? cals.first.id : null;
  }

  /// Create a single calendar event, return the event ID
  static Future<String?> createEvent(String calendarId, String title, DateTime time, {int durationMinutes = 0}) async {
    try {
      tz.Location location;
      try {
        final tzName = await FlutterTimezone.getLocalTimezone();
        location = tz.getLocation(tzName);
      } catch (_) {
        location = tz.local;
      }
      final start = tz.TZDateTime.from(time, location);
      final dur = durationMinutes >= 0 ? durationMinutes : 0;
      final end = start.add(Duration(minutes: dur));

      final event = dc.Event(calendarId,
        title: title,
        start: start,
        end: end,
        description: 'Created by أوان (Awan)',
      );
      final result = await _plugin.createOrUpdateEvent(event);
      if (result != null && result.isSuccess) return result.data;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete a single calendar event by eventId
  static Future<bool> deleteEvent(String calendarId, String eventId) async {
    try {
      final result = await _plugin.deleteEvent(calendarId, eventId);
      return result?.isSuccess ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sync an alarm's occurrences to the device calendar
  static Future<void> syncAlarmToCalendar(Al alarm) async {
    try {
      final calId = await effectiveCalendarId(alarm);
      if (calId == null) return;

      final now = DateTime.now();
      final horizonDays = alarm.calHorizonDays ?? st.calendarHorizonDays;
      final daysToSync = alarm.repeatMode == 'once' ? 1 : horizonDays;
      final title = alarm.label.isNotEmpty
          ? alarm.label
          : (alarm.prayer ? '${alarm.mins == 0 ? "موعد صلاة" : "${alarm.mins} دقيقة"} ${alarm.p}' : 'منبه أوان');

      // 1. Delete previously generated events that are now outside the schedule or need refresh
      for (final entry in alarm.calEventIds.entries) {
        await deleteEvent(calId, entry.value);
      }
      alarm.calEventIds.clear();

      // 2. Generate new events for the configured horizon
      var count = 0;
      for (var i = 0; i < daysToSync; i++) {
        final targetDate = now.add(Duration(days: i));
        final at = ringAt(alarm, targetDate);
        if (!at.isAfter(now)) continue;

        // Custom days filter
        if (alarm.repeatMode == 'custom' && !alarm.days.contains(targetDate.weekday)) {
          continue;
        }

        final eventId = await createEvent(
          calId,
          title,
          at,
          durationMinutes: alarm.calDuration,
        );
        if (eventId != null) {
          alarm.calEventIds['day_$i'] = eventId;
        }

        if (alarm.repeatMode == 'once' && ++count == 1) break;
      }

      if (alarm.calEventIds.isNotEmpty) {
        alarm.calendarId = calId;
      }
    } catch (_) {
      // best effort — never disrupt alarm scheduling
    }
  }

  /// Remove all calendar events created by this alarm
  static Future<void> removeAlarmFromCalendar(Al alarm) async {
    try {
      if (alarm.calEventIds.isEmpty) return;
      final calId = alarm.calendarId ?? st.defaultCalendarId;
      if (calId == null) return;
      for (final eventId in alarm.calEventIds.values) {
        await deleteEvent(calId, eventId);
      }
      alarm.calEventIds.clear();
    } catch (_) {
      // best effort
    }
  }
}

/// Sync all alarms' calendar events (fire-and-forget after reschedule)
Future<void> syncAllCalendarEvents() async {
  try {
    for (final a in alarms) {
      if (a.on && a.addToCalendar) {
        await CalendarService.syncAlarmToCalendar(a);
      } else if (a.calEventIds.isNotEmpty) {
        await CalendarService.removeAlarmFromCalendar(a);
      }
    }
    save();
  } catch (_) {
    // never crash
  }
}
