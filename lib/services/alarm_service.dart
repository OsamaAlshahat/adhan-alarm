import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/date_time_utils.dart';
import '../models/alarm_model.dart';
import '../models/settings_model.dart';
import '../screens/ring_screen.dart';
import 'calendar_service.dart';
import 'location_service.dart';
import 'storage_service.dart';

final navKey = GlobalKey<NavigatorState>();
final ringing = <int>{};
VoidCallback? homeRefresh;
StreamSubscription? _activeAlarmWatcher;

/// Background task dispatcher executed by WorkManager (even when app is terminated)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('st');
      if (s != null) st = Settings.from(jsonDecode(s));
      final l = prefs.getString('al');
      if (l != null) alarms = (jsonDecode(l) as List).map((e) => Al.from(e)).toList();
      await Alarm.init();
      await reschedule();
      try {
        await syncAllCalendarEvents();
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// Prayer times change every day, so we pre-schedule the next 14 days as exact
/// OS-level alarms. This runs on every app open and every change.
Future<void> reschedule() async {
  final now = DateTime.now();
  for (final s in await Alarm.getAlarms()) {
    if (s.dateTime.isAfter(now)) await Alarm.stop(s.id);
  }
  for (final a in alarms.where((a) => a.on)) {
    final validPath = (a.soundPath != null && File(a.soundPath!).existsSync())
        ? ((Platform.isIOS && a.soundPath!.toLowerCase().endsWith('.mp3')) ? 'assets/alarm.wav' : a.soundPath!)
        : 'assets/alarm.wav';
    final path = !a.sound ? 'assets/silent.wav' : validPath;
    var count = 0;
    for (var i = 0; i < 14; i++) {
      final targetDate = now.add(Duration(days: i));
      final at = ringAt(a, targetDate);
      if (!at.isAfter(now)) continue;

      // Filter by specific days of week if customized
      if (a.repeatMode == 'custom' && !a.days.contains(targetDate.weekday)) {
        continue;
      }

      final titleText = a.label.isNotEmpty ? a.label : (a.prayer ? '${a.mins} min ${a.p}' : 'Alarm');
      final isAr = st.language == 'ar' || (st.language == 'system' && WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ar');
      final stopText = isAr ? 'إيقاف' : 'Stop';
      final bodyText = a.notify ? formatTime(at) : '';

      final snoozeText = isAr ? 'غفوة ٥ دقائق' : 'Snooze 5 min';
      await Alarm.set(alarmSettings: AlarmSettings(
        id: a.id * 100 + i,
        dateTime: at,
        assetAudioPath: path,
        loopAudio: true,
        vibrate: a.vibrate,
        androidFullScreenIntent: true,
        warningNotificationOnKill: a.notify,
        androidSnoozeDuration: const Duration(minutes: 5),
        volumeSettings: VolumeSettings.fixed(volume: a.sound ? 0.9 : 0.0, volumeEnforced: a.sound),
        notificationSettings: NotificationSettings(
          title: a.notify ? titleText : '',
          body: bodyText,
          stopButton: a.notify ? stopText : null,
          androidSnoozeButton: a.notify ? snoozeText : null,
        ),
      ));

      // 'once' mode only schedules the first upcoming occurrence
      if (a.repeatMode == 'once' && ++count == 1) break;
    }
  }
}

void dismissRingScreen() {
  if (ringing.isNotEmpty) {
    ringing.clear();
    _activeAlarmWatcher?.cancel();
    _activeAlarmWatcher = null;
    navKey.currentState?.popUntil((route) => route.isFirst);
    homeRefresh?.call();
  }
}

void showRing(AlarmSettings s) {
  if (ringing.contains(s.id)) return;
  // If another ring screen is open, clear it
  if (ringing.isNotEmpty) {
    dismissRingScreen();
  }
  ringing.add(s.id);
  final a = alarms.where((x) => x.id == s.id ~/ 100).firstOrNull;
  if (a != null && a.repeatMode == 'once') {
    a.on = false;
    save();
  }

  // Watch for external dismissal (notification Stop or Snooze action button)
  _activeAlarmWatcher?.cancel();
  _activeAlarmWatcher = Stream.periodic(const Duration(milliseconds: 500)).listen((_) async {
    final stillRinging = await Alarm.isRinging(s.id);
    if (!stillRinging) {
      dismissRingScreen();
    }
  });

  navKey.currentState?.push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => RingScreen(s, a),
  )).then((_) {
    ringing.remove(s.id);
    _activeAlarmWatcher?.cancel();
    _activeAlarmWatcher = null;
    homeRefresh?.call();
  });
}

