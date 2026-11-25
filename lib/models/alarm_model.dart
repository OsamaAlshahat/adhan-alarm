import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/localization/ar.dart';
import '../core/localization/en.dart';
import '../core/localization/tr.dart';

class Al {
  int id;
  bool prayer;
  int minutes;
  String p;
  int sign;
  int mins;
  String label;
  bool on;
  String repeatMode; // 'once' (default), 'daily', 'custom'
  List<int> days;    // 1 (Monday) .. 7 (Sunday)
  bool notify, vibrate, sound;
  String? soundPath, soundName;
  bool addToCalendar;
  String? calendarId;         // per-alarm override; null = use app default
  int calDuration;            // duration in minutes for calendar events (default: 0)
  int? calHorizonDays;        // per-alarm horizon in days; null = use app default
  bool calRolling;            // false = one-time fixed range (default); true = continuously rolling window
  DateTime? calEndDate;       // fixed end date when calRolling is false
  Map<String, String> calEventIds; // key: "dayOffset_N", value: calendar eventId

  Al({
    required this.id,
    this.prayer = true,
    this.minutes = 420,
    this.p = 'fajr',
    this.sign = 1,
    this.mins = 10,
    this.label = '',
    this.on = true,
    this.repeatMode = 'once', // Default: only one time
    List<int>? days,
    this.notify = true,
    this.vibrate = true,
    this.sound = true,
    this.soundPath,
    this.soundName,
    this.addToCalendar = false,
    this.calendarId,
    this.calDuration = 0,
    this.calHorizonDays,
    this.calRolling = false,
    this.calEndDate,
    Map<String, String>? calEventIds,
  }) : days = days ?? [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday],
       calEventIds = calEventIds ?? {};

  bool get once => repeatMode == 'once';
  set once(bool v) => repeatMode = v ? 'once' : 'daily';

  Map<String, dynamic> toJson() => {
    'id': id,
    'prayer': prayer,
    'minutes': minutes,
    'p': p,
    'sign': sign,
    'mins': mins,
    'label': label,
    'on': on,
    'repeatMode': repeatMode,
    'days': days,
    'notify': notify,
    'vibrate': vibrate,
    'sound': sound,
    'soundPath': soundPath,
    'soundName': soundName,
    'addToCalendar': addToCalendar,
    'calendarId': calendarId,
    'calDuration': calDuration,
    'calHorizonDays': calHorizonDays,
    'calRolling': calRolling,
    'calEndDate': calEndDate?.toIso8601String(),
    'calEventIds': calEventIds,
  };

  factory Al.from(Map<String, dynamic> j) {
    final mode = j['repeatMode'] as String? ?? (j['once'] == false ? 'daily' : 'once');
    final rawDays = j['days'] as List?;
    final parsedDays = rawDays != null
        ? rawDays.map((e) => (e as num).toInt()).toList()
        : <int>[DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday];

    return Al(
      id: j['id'],
      prayer: j['prayer'] ?? true,
      minutes: j['minutes'] ?? 420,
      p: j['p'] ?? 'fajr',
      sign: j['sign'] ?? 1,
      mins: j['mins'] ?? 10,
      label: j['label'] ?? '',
      on: j['on'] ?? true,
      repeatMode: mode,
      days: parsedDays,
      notify: j['notify'] ?? true,
      vibrate: j['vibrate'] ?? true,
      sound: j['sound'] ?? true,
      soundPath: j['soundPath'],
      soundName: j['soundName'],
      addToCalendar: j['addToCalendar'] ?? false,
      calendarId: j['calendarId'],
      calDuration: (j['calDuration'] as num?)?.toInt() ?? 0,
      calHorizonDays: (j['calHorizonDays'] as num?)?.toInt(),
      calRolling: j['calRolling'] ?? false,
      calEndDate: j['calEndDate'] != null ? DateTime.tryParse(j['calEndDate']) : null,
      calEventIds: (j['calEventIds'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
    );
  }

  Al copy() => Al.from(jsonDecode(jsonEncode(toJson())));

  String desc(BuildContext context) {
    final ar = Tr.isAr(context);
    if (!prayer) return ar ? 'منبه عادي' : 'Normal alarm';
    final pName = Tr.prayer(context, p);
    if (mins == 0) {
      return ar ? 'في موعد صلاة $pName' : 'At $pName';
    }
    final h = mins ~/ 60;
    final m = mins % 60;
    String durText;
    if (ar) {
      if (h > 0 && m > 0) {
        durText = '$h س و $m د';
      } else if (h > 0) {
        durText = '$h ساعة';
      } else {
        durText = '$m دقيقة';
      }
      final rel = sign < 0 ? 'قبل' : 'بعد';
      return '$rel صلاة $pName بـ $durText';
    } else {
      if (h > 0 && m > 0) {
        durText = '${h}h ${m}m';
      } else if (h > 0) {
        durText = '${h}h';
      } else {
        durText = '$m min';
      }
      final rel = sign < 0 ? 'before' : 'after';
      return '$durText $rel $pName';
    }
  }

  String repeatText(BuildContext context) {
    final ar = Tr.isAr(context);
    if (repeatMode == 'once') return ar ? 'مرة واحدة' : 'Only once';
    if (repeatMode == 'daily') return ar ? 'كل يوم' : 'Every day';
    if (days.length == 7) return ar ? 'كل يوم' : 'Every day';
    if (days.isEmpty) return ar ? 'لم يتم تحديد أيام' : 'No days';

    final shortMap = <int, String>{
      DateTime.saturday: ar ? 'سبت' : 'Sat',
      DateTime.sunday: ar ? 'أحد' : 'Sun',
      DateTime.monday: ar ? 'إث' : 'Mon',
      DateTime.tuesday: ar ? 'ثل' : 'Tue',
      DateTime.wednesday: ar ? 'أر' : 'Wed',
      DateTime.thursday: ar ? 'خم' : 'Thu',
      DateTime.friday: ar ? 'جم' : 'Fri',
    };
    final orderedList = (ar ? weekDaysAr : weekDaysEn)
        .map((x) => x['day'] as int)
        .where((d) => days.contains(d))
        .map((d) => shortMap[d] ?? '$d');

    return orderedList.join(ar ? '، ' : ', ');
  }

  String actions(BuildContext context) {
    final ar = Tr.isAr(context);
    final list = [
      if (sound) ar ? 'رنين' : 'Ring',
      if (vibrate) ar ? 'اهتزاز' : 'Vibrate',
      if (notify) ar ? 'إشعار' : 'Notify',
    ];
    return list.join(ar ? '، ' : ', ');
  }
}

