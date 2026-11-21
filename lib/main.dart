import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:adhan/adhan.dart';
import 'package:alarm/alarm.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

const dailyRescheduleTaskKey = 'adhan_alarm_daily_reschedule';

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
      return true;
    } catch (_) {
      return false;
    }
  });
}

const prayers = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

const methods = {
  'egyptian': CalculationMethod.egyptian,
  'mwl': CalculationMethod.muslim_world_league,
  'makkah': CalculationMethod.umm_al_qura,
  'karachi': CalculationMethod.karachi,
  'isna': CalculationMethod.north_america,
};

// country -> [city, lat, lng] (built in, offline)
const cities = <String, List<List<Object>>>{
  'Egypt': [['Alexandria', 31.2, 29.92], ['Cairo', 30.04, 31.24], ['Giza', 30.01, 31.21], ['Mansoura', 31.04, 31.38], ['Tanta', 30.79, 31.0], ['Port Said', 31.27, 32.3], ['Suez', 29.97, 32.55], ['Luxor', 25.69, 32.64], ['Aswan', 24.09, 32.9], ['Assiut', 27.18, 31.18]],
  'Saudi Arabia': [['Makkah', 21.42, 39.83], ['Madinah', 24.47, 39.61], ['Riyadh', 24.71, 46.68], ['Jeddah', 21.54, 39.17]],
  'UAE': [['Dubai', 25.2, 55.27], ['Abu Dhabi', 24.45, 54.38]],
  'Jordan': [['Amman', 31.95, 35.93]], 'Palestine': [['Jerusalem', 31.77, 35.21]],
  'Kuwait': [['Kuwait City', 29.38, 47.99]], 'Qatar': [['Doha', 25.29, 51.53]],
  'Iraq': [['Baghdad', 33.31, 44.37]], 'Morocco': [['Casablanca', 33.57, -7.59]],
  'Algeria': [['Algiers', 36.75, 3.06]], 'Tunisia': [['Tunis', 36.81, 10.18]],
  'Turkey': [['Istanbul', 41.01, 28.98]], 'Pakistan': [['Karachi', 24.86, 67.01]],
  'Indonesia': [['Jakarta', -6.2, 106.85]], 'United Kingdom': [['London', 51.51, -0.13]],
  'United States': [['New York', 40.71, -74.01]],
};

const weekDaysAr = [
  {'day': DateTime.saturday, 'name': 'السبت', 'short': 'سبت'},
  {'day': DateTime.sunday, 'name': 'الأحد', 'short': 'أحد'},
  {'day': DateTime.monday, 'name': 'الإثنين', 'short': 'إث'},
  {'day': DateTime.tuesday, 'name': 'الثلاثاء', 'short': 'ثل'},
  {'day': DateTime.wednesday, 'name': 'الأربعاء', 'short': 'أر'},
  {'day': DateTime.thursday, 'name': 'الخميس', 'short': 'خم'},
  {'day': DateTime.friday, 'name': 'الجمعة', 'short': 'جم'},
];

const weekDaysEn = [
  {'day': DateTime.monday, 'name': 'Monday', 'short': 'Mon'},
  {'day': DateTime.tuesday, 'name': 'Tuesday', 'short': 'Tue'},
  {'day': DateTime.wednesday, 'name': 'Wednesday', 'short': 'Wed'},
  {'day': DateTime.thursday, 'name': 'Thursday', 'short': 'Thu'},
  {'day': DateTime.friday, 'name': 'Friday', 'short': 'Fri'},
  {'day': DateTime.saturday, 'name': 'Saturday', 'short': 'Sat'},
  {'day': DateTime.sunday, 'name': 'Sunday', 'short': 'Sun'},
];

/// Localization helper for English and Arabic with automatic fallback
class Tr {
  static bool isAr(BuildContext? context) {
    if (context != null) {
      return Localizations.localeOf(context).languageCode == 'ar';
    }
    if (st.language == 'ar') return true;
    if (st.language == 'en') return false;
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ar';
  }

  static String t(BuildContext context, String en, String ar) => isAr(context) ? ar : en;

  static String prayer(BuildContext context, String p) {
    final ar = isAr(context);
    switch (p) {
      case 'fajr': return ar ? 'الفجر' : 'Fajr';
      case 'sunrise': return ar ? 'الشروق' : 'Sunrise';
      case 'dhuhr': return ar ? 'الظهر' : 'Dhuhr';
      case 'asr': return ar ? 'العصر' : 'Asr';
      case 'maghrib': return ar ? 'المغرب' : 'Maghrib';
      case 'isha': return ar ? 'العشاء' : 'Isha';
      default: return p;
    }
  }

  static String method(BuildContext context, String m) {
    final ar = isAr(context);
    switch (m) {
      case 'egyptian': return ar ? 'الهيئة المصرية العامة للمساحة' : 'Egyptian General Authority';
      case 'mwl': return ar ? 'رابطة العالم الإسلامي' : 'Muslim World League';
      case 'makkah': return ar ? 'أم القرى (مكة المكرمة)' : 'Umm al-Qura (Makkah)';
      case 'karachi': return ar ? 'جامعة العلوم الإسلامية بكراتشي' : 'Karachi';
      case 'isna': return ar ? 'الجمعية الإسلامية لأمريكا الشمالية' : 'ISNA (North America)';
      default: return m;
    }
  }

  static String country(BuildContext context, String c) {
    final ar = isAr(context);
    if (!ar) return c;
    switch (c) {
      case 'Egypt': return 'مصر';
      case 'Saudi Arabia': return 'المملكة العربية السعودية';
      case 'UAE': return 'الإمارات';
      case 'Jordan': return 'الأردن';
      case 'Palestine': return 'فلسطين';
      case 'Kuwait': return 'الكويت';
      case 'Qatar': return 'قطر';
      case 'Iraq': return 'العراق';
      case 'Morocco': return 'المغرب';
      case 'Algeria': return 'الجزائر';
      case 'Tunisia': return 'تونس';
      case 'Turkey': return 'تركيا';
      case 'Pakistan': return 'باكستان';
      case 'Indonesia': return 'إندونيسيا';
      case 'United Kingdom': return 'المملكة المتحدة';
      case 'United States': return 'الولايات المتحدة';
      default: return c;
    }
  }

  static String city(BuildContext context, String ct) {
    final ar = isAr(context);
    if (!ar) return ct;
    switch (ct) {
      case 'Alexandria': return 'الإسكندرية';
      case 'Cairo': return 'القاهرة';
      case 'Giza': return 'الجيزة';
      case 'Mansoura': return 'المنصورة';
      case 'Tanta': return 'طنطا';
      case 'Port Said': return 'بورسعيد';
      case 'Suez': return 'السويس';
      case 'Luxor': return 'الأقصر';
      case 'Aswan': return 'أسوان';
      case 'Assiut': return 'أسيوط';
      case 'Makkah': return 'مكة المكرمة';
      case 'Madinah': return 'المدينة المنورة';
      case 'Riyadh': return 'الرياض';
      case 'Jeddah': return 'جدة';
      case 'Dubai': return 'دبي';
      case 'Abu Dhabi': return 'أبوظبي';
      case 'Amman': return 'عمان';
      case 'Jerusalem': return 'القدس';
      case 'Kuwait City': return 'مدينة الكويت';
      case 'Doha': return 'الدوحة';
      case 'Baghdad': return 'بغداد';
      case 'Casablanca': return 'الدار البيضاء';
      case 'Algiers': return 'الجزائر العاصمة';
      case 'Tunis': return 'تونس العاصمة';
      case 'Istanbul': return 'إسطنبول';
      case 'Karachi': return 'كراتشي';
      case 'Jakarta': return 'جاكرتا';
      case 'London': return 'لندن';
      case 'New York': return 'نيويورك';
      case 'My location': return 'موقعي الحالي';
      case 'GPS': return 'GPS';
      default: return ct;
    }
  }
}

class Settings {
  String country = 'Egypt', city = 'Alexandria', method = 'egyptian';
  double lat = 31.2, lng = 29.92;
  String timeFormat = 'system'; // 'system', '12h', '24h'
  String language = 'system';   // 'system', 'en', 'ar'
  String? defaultCalendarId;    // device calendar ID for "Add to Calendar"
  int calendarHorizonDays = 30; // Precalculated days for calendar events (14, 30, 60, 90, 180, 365)

  Map<String, dynamic> toJson() => {
    'country': country,
    'city': city,
    'method': method,
    'lat': lat,
    'lng': lng,
    'timeFormat': timeFormat,
    'language': language,
    'defaultCalendarId': defaultCalendarId,
    'calendarHorizonDays': calendarHorizonDays,
  };

  Settings();
  Settings.from(Map<String, dynamic> j) {
    country = j['country'] ?? 'Egypt';
    city = j['city'] ?? 'Alexandria';
    method = j['method'] ?? 'egyptian';
    lat = (j['lat'] as num?)?.toDouble() ?? 31.2;
    lng = (j['lng'] as num?)?.toDouble() ?? 29.92;
    timeFormat = j['timeFormat'] ?? 'system';
    language = j['language'] ?? 'system';
    defaultCalendarId = j['defaultCalendarId'];
    calendarHorizonDays = (j['calendarHorizonDays'] as num?)?.toInt() ?? 30;
  }
}

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

late SharedPreferences prefs;
Settings st = Settings();
List<Al> alarms = [];
final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier<Locale?>(null);

Locale? getLocaleFromSetting(String lang) {
  if (lang == 'ar') return const Locale('ar');
  if (lang == 'en') return const Locale('en');
  return null; // System default: follow phone language
}

void save() {
  prefs.setString('st', jsonEncode(st.toJson()));
  prefs.setString('al', jsonEncode(alarms.map((a) => a.toJson()).toList()));
}

PrayerTimes timesFor(DateTime d) {
  final params = methods[st.method]!.getParameters();
  params.madhab = Madhab.shafi;
  return PrayerTimes(Coordinates(st.lat, st.lng), DateComponents.from(d), params);
}

DateTime? prayerTime(PrayerTimes t, String p) {
  switch (p) {
    case 'fajr': return t.fajr.toLocal();
    case 'sunrise': return t.sunrise.toLocal();
    case 'dhuhr': return t.dhuhr.toLocal();
    case 'asr': return t.asr.toLocal();
    case 'maghrib': return t.maghrib.toLocal();
    default: return t.isha.toLocal();
  }
}

DateTime ringAt(Al a, DateTime day) {
  if (!a.prayer) return DateTime(day.year, day.month, day.day, a.minutes ~/ 60, a.minutes % 60);
  final t = prayerTime(timesFor(day), a.p)!;
  return DateTime(t.year, t.month, t.day, t.hour, t.minute).add(Duration(minutes: a.sign * a.mins));
}

bool is24HourFormat(BuildContext? context) {
  if (st.timeFormat == '12h') return false;
  if (st.timeFormat == '24h') return true;
  if (context != null) {
    return MediaQuery.alwaysUse24HourFormatOf(context);
  }
  return WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
}

String formatTime(DateTime d, [BuildContext? context]) {
  final use24 = is24HourFormat(context);
  final m = d.minute.toString().padLeft(2, '0');
  if (use24) {
    return '${d.hour.toString().padLeft(2, '0')}:$m';
  }
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ar = Tr.isAr(context);
  final period = d.hour < 12 ? (ar ? 'ص' : 'AM') : (ar ? 'م' : 'PM');
  return '$h:$m $period';
}

String formatCalDuration(BuildContext ctx, int minutes) {
  final ar = Tr.isAr(ctx);
  if (minutes <= 0) {
    return ar ? '0 دقيقة (تنبيه فقط)' : '0 min (reminder)';
  } else if (minutes < 60) {
    return ar ? '$minutes دقيقة' : '$minutes min';
  } else if (minutes == 60) {
    return ar ? 'ساعة (60 د)' : '1 hour';
  } else if (minutes == 90) {
    return ar ? 'ساعة ونصف (90 د)' : '1.5 hours (90 min)';
  } else if (minutes == 120) {
    return ar ? 'ساعتان (120 د)' : '2 hours';
  } else if (minutes == 180) {
    return ar ? '3 ساعات (180 د)' : '3 hours';
  } else {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) {
      return ar ? '$h ساعات' : '$h hours';
    } else {
      return ar ? '$h س و $m د' : '${h}h ${m}m';
    }
  }
}

/// Prayer times change every day, so we pre-schedule the next 14 days as exact
/// OS-level alarms. This runs on every app open and every change.
Future<void> reschedule() async {
  final now = DateTime.now();
  for (final s in await Alarm.getAlarms()) {
    if (s.dateTime.isAfter(now)) await Alarm.stop(s.id);
  }
  for (final a in alarms.where((a) => a.on)) {
    final path = !a.sound
        ? 'assets/silent.wav'
        : ((a.soundPath != null && File(a.soundPath!).existsSync()) ? a.soundPath! : 'assets/alarm.wav');
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

const platformFullscreen = MethodChannel('com.adhan_alarm.app/fullscreen_settings');

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

  if (name == null || name.isEmpty) {
    if (isSamsung) {
      name = 'Samsung Calendar';
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

  /// Request calendar permissions using both permission_handler and device_calendar
  static Future<bool> requestPermissions() async {
    try {
      var isGranted = await Permission.calendar.isGranted;
      if (!isGranted) {
        final res = await Permission.calendar.request();
        isGranted = res.isGranted;
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

      // 3. Put device default / primary calendar first (e.g. Samsung Calendar)
      uniqueList.sort((a, b) {
        if (a.isDefault == true && b.isDefault != true) return -1;
        if (b.isDefault == true && a.isDefault != true) return 1;
        final aIsLocal = a.accountType?.toLowerCase().contains('samsung') == true || a.accountName?.toLowerCase() == 'phone';
        final bIsLocal = b.accountType?.toLowerCase().contains('samsung') == true || b.accountName?.toLowerCase() == 'phone';
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

  /// Delete a single calendar event
  static Future<void> deleteEvent(String calendarId, String eventId) async {
    try {
      await _plugin.deleteEvent(calendarId, eventId);
    } catch (_) {
      // best effort
    }
  }

  /// Sync all upcoming occurrences of an alarm to the calendar
  static Future<void> syncAlarmToCalendar(Al alarm) async {
    try {
      final calId = await effectiveCalendarId(alarm);
      if (calId == null) return;

      // Remove old events first
      await removeAlarmFromCalendar(alarm);

      final now = DateTime.now();
      final title = alarm.label.isNotEmpty
          ? alarm.label
          : (alarm.prayer ? '${alarm.p} alarm' : 'Awan alarm');

      final newEventIds = <String, String>{};
      final alarmHorizon = alarm.calHorizonDays;
      final horizon = (alarmHorizon != null && alarmHorizon > 0)
          ? alarmHorizon
          : ((st.calendarHorizonDays > 0) ? st.calendarHorizonDays : 30);
      for (var i = 0; i < horizon; i++) {
        final targetDate = now.add(Duration(days: i));
        final at = ringAt(alarm, targetDate);
        if (!at.isAfter(now)) continue;

        // Filter by specific days if custom
        if (alarm.repeatMode == 'custom' && !alarm.days.contains(targetDate.weekday)) continue;

        final eventId = await createEvent(calId, title, at, durationMinutes: alarm.calDuration);
        if (eventId != null) {
          newEventIds['day_$i'] = eventId;
        }

        // Once mode: only one occurrence
        if (alarm.repeatMode == 'once' && newEventIds.isNotEmpty) break;
      }

      alarm.calEventIds = newEventIds;
      // Store the calendar ID actually used
      if (alarm.calendarId == null && calId != st.defaultCalendarId) {
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

Future<bool> canUseFullScreenIntent() async {
  if (!Platform.isAndroid) return true;
  try {
    final res = await platformFullscreen.invokeMethod<bool>('canUseFullScreenIntent');
    return res ?? true;
  } catch (_) {
    return true;
  }
}

Future<void> openFullScreenIntentSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await platformFullscreen.invokeMethod('openFullScreenIntentSettings');
  } catch (_) {
    await openAppSettings();
  }
}

final navKey = GlobalKey<NavigatorState>();
final ringing = <int>{};
VoidCallback? homeRefresh;
StreamSubscription? _activeAlarmWatcher;

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
  // Poll briefly every 500ms while ring screen is active to detect if alarm stopped ringing externally
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

class RingScreen extends StatelessWidget {
  final AlarmSettings s;
  final Al? a;
  const RingScreen(this.s, this.a, {super.key});

  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final nav = Navigator.of(c);
    final title = a == null
        ? Tr.t(c, 'Alarm', 'منبه')
        : (a!.label.isNotEmpty ? a!.label : a!.desc(c));

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF072426),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0F3E41),
                    border: Border.all(color: const Color(0xFFE5B54F).withOpacity(0.4), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE5B54F).withOpacity(0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.alarm, size: 54, color: Color(0xFFE5B54F)),
                ),
                const SizedBox(height: 18),
                Text(
                  formatTime(s.dateTime, c),
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: Color(0xFFF9F5EC)),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, color: Color(0xFFE5B54F), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F3E41),
                      foregroundColor: const Color(0xFFF9F5EC),
                    ),
                    onPressed: () async {
                      await Alarm.stop(s.id);
                      await Alarm.set(alarmSettings: s.copyWith(
                        id: 9000000 + Random().nextInt(99999),
                        dateTime: DateTime.now().add(const Duration(minutes: 5)),
                      ));
                      nav.pop();
                    },
                    child: Text(Tr.t(c, 'Snooze 5 min', 'غفوة 5 دقائق'), style: const TextStyle(fontSize: 20)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE5B54F),
                      foregroundColor: const Color(0xFF072426),
                    ),
                    onPressed: () async {
                      await Alarm.stop(s.id);
                      nav.pop();
                    },
                    child: Text(Tr.t(c, 'Stop', 'إيقاف'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone database
  tz.initializeTimeZones();
  try {
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));
  } catch (_) {
    // fallback to UTC if timezone detection fails
  }

  prefs = await SharedPreferences.getInstance();
  final s = prefs.getString('st');
  if (s != null) st = Settings.from(jsonDecode(s));
  final l = prefs.getString('al');
  if (l != null) alarms = (jsonDecode(l) as List).map((e) => Al.from(e)).toList();

  appLocaleNotifier.value = getLocaleFromSetting(st.language);

  await Alarm.init();
  await Permission.notification.request();

  // Android-specific permissions for Android 13, 14, and 15
  if (Platform.isAndroid) {
    await Permission.scheduleExactAlarm.request();
    await Permission.ignoreBatteryOptimizations.request();
    await Permission.systemAlertWindow.request();
  }

  await reschedule();

  // Fire-and-forget calendar sync
  syncAllCalendarEvents();

  // Initialize periodic background worker (guarded for Android & iOS)
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      );
      await Workmanager().registerPeriodicTask(
        'daily_prayer_reschedule_task',
        dailyRescheduleTaskKey,
        frequency: const Duration(hours: 24),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
        ),
      );
    }
  } catch (e) {
    debugPrint('Workmanager init: $e');
  }

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext c) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: appLocaleNotifier,
      builder: (context, activeLocale, _) {
        return MaterialApp(
          title: 'Awan',
          navigatorKey: navKey,
          locale: activeLocale,
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF0C5A58),
            scaffoldBackgroundColor: const Color(0xFFF4F7F6),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF147A78),
            scaffoldBackgroundColor: const Color(0xFF051719),
            brightness: Brightness.dark,
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          home: const Home(),
        );
      },
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _H();
}

class _H extends State<Home> with WidgetsBindingObserver {
  int tab = 0;
  String _alarmFilter = 'all'; // 'all', 'calendar', 'normal'
  StreamSubscription<AlarmSettings>? sub;
  List<dc.Calendar>? _availableCalendars;
  bool _loadingCalendars = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    homeRefresh = () {
      if (mounted) setState(() {});
    };
    sub = Alarm.ringStream.stream.listen(showRing);
    _checkRingingAlarms();
    _refreshCalendars();
  }

  Future<void> _refreshCalendars() async {
    if (!mounted) return;
    setState(() => _loadingCalendars = true);
    final cals = await CalendarService.getWritableCalendars();
    if (mounted) {
      setState(() {
        _availableCalendars = cals;
        _loadingCalendars = false;
        if (cals.isNotEmpty) {
          final isCurrentValid = st.defaultCalendarId != null && cals.any((c) => c.id == st.defaultCalendarId);
          if (!isCurrentValid) {
            st.defaultCalendarId = cals.first.id;
            save();
          }
        }
      });
    }
  }

  /// Check if any alarm is currently ringing and show the full-screen UI
  Future<void> _checkRingingAlarms() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    
    // If RingScreen is already showing, check if it's still ringing
    if (ringing.isNotEmpty) {
      final activeId = ringing.first;
      final stillRinging = await Alarm.isRinging(activeId);
      if (!stillRinging) {
        dismissRingScreen();
      }
      return;
    }

    final now = DateTime.now();
    for (final s in await Alarm.getAlarms()) {
      final isRinging = await Alarm.isRinging(s.id);
      if (isRinging) {
        showRing(s);
        return;
      }
      if (!s.dateTime.isAfter(now) && now.difference(s.dateTime).inMinutes < 10) {
        final ringingNow = await Alarm.isRinging(s.id);
        if (ringingNow) {
          showRing(s);
          return;
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkRingingAlarms();
      _refreshCalendars();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sub?.cancel();
    homeRefresh = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(tab == 0 ? Tr.t(c, 'Awan', 'أوان') : Tr.t(c, 'Settings', 'الإعدادات')),
    ),
    body: SafeArea(top: false, child: tab == 0 ? alarmsView() : settingsView()),
    floatingActionButton: tab == 0
        ? FloatingActionButton.extended(
            onPressed: () => openSheet(),
            icon: const Icon(Icons.add),
            label: Text(Tr.t(c, 'New alarm', 'منبه جديد')),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      destinations: [
        NavigationDestination(icon: const Icon(Icons.alarm), label: Tr.t(c, 'Alarms', 'المنبهات')),
        NavigationDestination(icon: const Icon(Icons.settings), label: Tr.t(c, 'Settings', 'الإعدادات')),
      ],
    ),
  );

  Widget alarmsView() {
    final t = timesFor(DateTime.now());
    final filteredAlarms = alarms.where((a) {
      if (_alarmFilter == 'calendar') return a.addToCalendar;
      if (_alarmFilter == 'normal') return !a.addToCalendar;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final p in prayers)
                  Column(
                    children: [
                      Text(Tr.prayer(context, p), style: const TextStyle(fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        formatTime(prayerTime(t, p)!, context),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Filter Bar (Calendar / Normal / All)
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'all',
                label: Text(Tr.t(context, 'All', 'الكل')),
                icon: const Icon(Icons.apps, size: 16),
              ),
              ButtonSegment(
                value: 'calendar',
                label: Text(Tr.t(context, 'Calendar', 'التقويم')),
                icon: const Icon(Icons.calendar_month, size: 16),
              ),
              ButtonSegment(
                value: 'normal',
                label: Text(Tr.t(context, 'Normal', 'عادي')),
                icon: const Icon(Icons.alarm, size: 16),
              ),
            ],
            selected: {_alarmFilter},
            onSelectionChanged: (s) => setState(() => _alarmFilter = s.first),
          ),
        ),
        const SizedBox(height: 8),

        if (alarms.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                Tr.t(context, 'No alarms yet. Tap “New alarm”.', 'لا توجد منبهات حالياً. اضغط على "منبه جديد".'),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else if (filteredAlarms.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                _alarmFilter == 'calendar'
                    ? Tr.t(context, 'No alarms with calendar sync.', 'لا توجد منبهات مرتبطة بالتقويم.')
                    : Tr.t(context, 'No normal alarms without calendar.', 'لا توجد منبهات عادية بدون تقويم.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
        for (final a in filteredAlarms)
          Card(
            child: ListTile(
              onTap: () => openSheet(a),
              title: Row(
                children: [
                  Text(
                    formatTime(ringAt(a, DateTime.now()), context),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
                  ),
                  const Spacer(),
                  if (a.addToCalendar)
                    Container(
                      margin: const EdgeInsets.only(right: 4, left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month, size: 13, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            Tr.t(context, 'Calendar', 'في التقويم'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                '${a.label.isEmpty ? '' : '${a.label} · '}${a.desc(context)} · ${a.repeatText(context)}\n${a.actions(context)}',
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: a.on,
                    onChanged: (v) async {
                      a.on = v;
                      save();
                      await reschedule();
                      // Remove calendar events when alarm is turned off
                      if (!v && a.calEventIds.isNotEmpty) {
                        CalendarService.removeAlarmFromCalendar(a).then((_) => save());
                      }
                      // Re-sync calendar events when alarm is turned on
                      if (v && a.addToCalendar) {
                        CalendarService.syncAlarmToCalendar(a).then((_) => save());
                      }
                      setState(() {});
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      // Remove calendar events before deleting alarm
                      if (a.calEventIds.isNotEmpty) {
                        await CalendarService.removeAlarmFromCalendar(a);
                      }
                      alarms.remove(a);
                      save();
                      await reschedule();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 90),
      ],
    );
  }

  Widget settingsView() {
    final list = cities[st.country] ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Language Setting
        Text(Tr.t(context, 'Language', 'اللغة'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: st.language,
          decoration: InputDecoration(
            labelText: Tr.t(context, 'App Language', 'لغة التطبيق'),
            prefixIcon: const Icon(Icons.language),
          ),
          items: [
            DropdownMenuItem(value: 'system', child: Text(Tr.t(context, 'System default (follows phone)', 'تلقائي (حسب لغة الهاتف)'))),
            const DropdownMenuItem(value: 'en', child: Text('English')),
            const DropdownMenuItem(value: 'ar', child: Text('العربية (Arabic)')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              st.language = v;
            });
            appLocaleNotifier.value = getLocaleFromSetting(v);
            save();
          },
        ),
        const SizedBox(height: 20),

        // Time Format Setting (12h / 24h)
        Text(Tr.t(context, 'Time format', 'تنسيق الوقت'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: st.timeFormat,
          decoration: InputDecoration(
            labelText: Tr.t(context, 'Clock display', 'عرض الساعة'),
            prefixIcon: const Icon(Icons.schedule),
          ),
          items: [
            DropdownMenuItem(value: 'system', child: Text(Tr.t(context, 'System default (follows phone)', 'تلقائي (حسب نظام الهاتف)'))),
            DropdownMenuItem(value: '12h', child: Text(Tr.t(context, '12-hour format (AM / PM)', 'نظام 12 ساعة (ص / م)'))),
            DropdownMenuItem(value: '24h', child: Text(Tr.t(context, '24-hour format', 'نظام 24 ساعة'))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              st.timeFormat = v;
            });
            save();
            reschedule();
          },
        ),
        const SizedBox(height: 20),

        // Location & Calculation Method
        Text(Tr.t(context, 'Location & Prayer calculation', 'الموقع وحساب مواقيت الصلاة'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: cities.containsKey(st.country) ? st.country : null,
          decoration: InputDecoration(labelText: Tr.t(context, 'Country', 'الدولة'), prefixIcon: const Icon(Icons.public)),
          items: [
            for (final k in cities.keys)
              DropdownMenuItem(value: k, child: Text(Tr.country(context, k))),
          ],
          onChanged: (v) {
            if (v == null) return;
            final f = cities[v]!.first;
            setState(() {
              st.country = v;
              st.city = f[0] as String;
              st.lat = f[1] as double;
              st.lng = f[2] as double;
            });
            save();
            reschedule();
            syncAllCalendarEvents();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: list.any((x) => x[0] == st.city) ? st.city : null,
          decoration: InputDecoration(labelText: Tr.t(context, 'City', 'المدينة'), prefixIcon: const Icon(Icons.location_city)),
          items: [
            for (final x in list)
              DropdownMenuItem(value: x[0] as String, child: Text(Tr.city(context, x[0] as String))),
          ],
          onChanged: (v) {
            if (v == null) return;
            final x = list.firstWhere((e) => e[0] == v);
            setState(() {
              st.city = v;
              st.lat = x[1] as double;
              st.lng = x[2] as double;
            });
            save();
            reschedule();
            syncAllCalendarEvents();
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.my_location),
          label: Text(Tr.t(context, 'Use GPS', 'استخدام GPS')),
          onPressed: useGps,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: st.method,
          decoration: InputDecoration(
            labelText: Tr.t(context, 'Calculation method', 'طريقة الحساب'),
            prefixIcon: const Icon(Icons.calculate),
          ),
          items: [
            for (final m in methods.keys)
              DropdownMenuItem(value: m, child: Text(Tr.method(context, m))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => st.method = v);
            save();
            reschedule();
            syncAllCalendarEvents();
          },
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 24),
          Text(Tr.t(context, 'Alarm & Lockscreen permissions', 'أذونات المنبه وشاشة القفل'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Tr.t(
                      context,
                      'To wake up the screen and display the full-screen alarm over your lock screen on Android 14/15:\n\n'
                      '1. Tap "Full-screen alarm permission" below to grant special access.\n'
                      '2. Tap "Appear on top" to ensure the alarm can display over other apps.\n'
                      '3. Disable battery optimization so alarms ring on time.',
                      'لتشغيل الشاشة وعرض تنبيهات أوان ملء الشاشة على شاشة القفل في أندرويد ١٤ / ١٥:\n\n'
                      '١. اضغط "إذن منبه ملء الشاشة" بالأسفل لمنح الإذن الخاص.\n'
                      '٢. اضغط "الظهور فوق التطبيقات" للتأكد من قدرة المنبه على الظهور.\n'
                      '٣. استثنِ التطبيق من توفير الطاقة لضمان عمل المنبه في موعده.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.fullscreen, size: 18),
                        label: Text(Tr.t(context, 'Full-screen alarm permission', 'إذن منبه ملء الشاشة')),
                        onPressed: () => openFullScreenIntentSettings(),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.layers, size: 18),
                        label: Text(Tr.t(context, 'Appear on top', 'الظهور في المقدمة')),
                        onPressed: () async {
                          await Permission.systemAlertWindow.request();
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.settings, size: 18),
                        label: Text(Tr.t(context, 'App Settings', 'إعدادات التطبيق')),
                        onPressed: () => openAppSettings(),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.battery_charging_full, size: 18),
                        label: Text(Tr.t(context, 'Battery optimization', 'استثناء توفير الطاقة')),
                        onPressed: () async {
                          await Permission.ignoreBatteryOptimizations.request();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(Tr.t(context, 'Battery optimization requested', 'تم طلب استثناء توفير الطاقة'))),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        // ===== Calendar Integration Section =====
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Tr.t(context, 'Calendar integration', 'ربط التقويم'), style: Theme.of(context).textTheme.titleSmall),
            IconButton(
              icon: _loadingCalendars
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
              tooltip: Tr.t(context, 'Refresh calendars', 'تحديث التقويمات'),
              onPressed: _loadingCalendars ? null : _refreshCalendars,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Tr.t(
                    context,
                    'Select a default calendar for alarms with "Add to Calendar" enabled. Each alarm event will appear in your chosen calendar.',
                    'اختر تقويماً افتراضياً للمنبهات التي تم تفعيل "إضافة للتقويم" لها. ستظهر أحداث المنبه في التقويم المختار.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_loadingCalendars && _availableCalendars == null)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (_availableCalendars == null || _availableCalendars!.isEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Tr.t(
                          context,
                          'Please grant calendar permission so Awan can access your phone calendar.',
                          'يرجى منح إذن التقويم ليتمكن أوان من الوصول إلى تقويم هاتفك.',
                        ),
                        style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(Tr.t(context, 'Grant Calendar Permission', 'منح إذن التقويم')),
                            onPressed: () async {
                              await CalendarService.requestPermissions();
                              await _refreshCalendars();
                            },
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.settings, size: 18),
                            label: Text(Tr.t(context, 'App Settings', 'إعدادات التطبيق')),
                            onPressed: () => openAppSettings(),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  DropdownButtonFormField<String>(
                    value: (_availableCalendars!.any((c) => c.id == st.defaultCalendarId))
                        ? st.defaultCalendarId
                        : _availableCalendars!.first.id,
                    decoration: InputDecoration(
                      labelText: Tr.t(context, 'Default calendar', 'التقويم الافتراضي'),
                      prefixIcon: const Icon(Icons.calendar_month),
                    ),
                    items: [
                      for (final cal in _availableCalendars!)
                        DropdownMenuItem(
                          value: cal.id,
                          child: Text(
                            calendarDisplayName(cal),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() { st.defaultCalendarId = v; });
                      save();
                      syncAllCalendarEvents();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: [14, 30, 60, 90, 180, 365].contains(st.calendarHorizonDays)
                        ? st.calendarHorizonDays
                        : 30,
                    decoration: InputDecoration(
                      labelText: Tr.t(context, 'Schedule ahead for (default)', 'إضافة للتقويم مسبقاً لمدة (افتراضي)'),
                      prefixIcon: const Icon(Icons.date_range),
                      helperText: Tr.t(
                        context,
                        'Default period to precalculate events for calendar alarms',
                        'الفترة الافتراضية لحساب وإضافة الأحداث للتقويم مسبقاً',
                      ),
                      helperMaxLines: 2,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 14,
                        child: Text(Tr.t(context, '14 days (2 weeks)', '14 يوماً (أسبوعان)')),
                      ),
                      DropdownMenuItem(
                        value: 30,
                        child: Text(Tr.t(context, '30 days (1 month)', '30 يوماً (شهر)')),
                      ),
                      DropdownMenuItem(
                        value: 60,
                        child: Text(Tr.t(context, '60 days (2 months)', '60 يوماً (شهران)')),
                      ),
                      DropdownMenuItem(
                        value: 90,
                        child: Text(Tr.t(context, '90 days (3 months)', '90 يوماً (3 أشهر)')),
                      ),
                      DropdownMenuItem(
                        value: 180,
                        child: Text(Tr.t(context, '180 days (6 months)', '180 يوماً (6 أشهر)')),
                      ),
                      DropdownMenuItem(
                        value: 365,
                        child: Text(Tr.t(context, '365 days (1 year)', '365 يوماً (سنة كاملة)')),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() { st.calendarHorizonDays = v; });
                      save();
                      syncAllCalendarEvents();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> useGps() async {
    final m = ScaffoldMessenger.of(context);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      m.showSnackBar(SnackBar(content: Text(Tr.t(context, 'Location permission denied. Choose your city manually.', 'تم رفض إذن الموقع. يرجى اختيار المدينة يدوياً.'))));
      return;
    }
    final p = await Geolocator.getCurrentPosition();
    String? bc, bn;
    double bd = 1e9;
    final bl = p.latitude, bg = p.longitude;
    cities.forEach((k, l) {
      for (final x in l) {
        final d = Geolocator.distanceBetween(p.latitude, p.longitude, x[1] as double, x[2] as double) / 1000;
        if (d < bd) {
          bd = d;
          bc = k;
          bn = x[0] as String;
        }
      }
    });
    setState(() {
      st.lat = bl;
      st.lng = bg;
      st.country = bd < 150 ? bc! : 'GPS';
      st.city = bd < 150 ? bn! : Tr.t(context, 'My location', 'موقعي الحالي');
    });
    save();
    await reschedule();
    syncAllCalendarEvents();
    m.showSnackBar(SnackBar(content: Text('${Tr.t(context, "Location set: ", "تم تحديد الموقع: ")}${Tr.city(context, st.city)}')));
  }

  Future<void> pickSound(Al e, void Function(void Function()) set) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final ext = f.name.contains('.') ? f.name.substring(f.name.lastIndexOf('.')) : '.mp3';
    final dest = '${dir.path}/sound_${e.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(f.path!).copy(dest);
    set(() {
      e.soundPath = dest;
      e.soundName = f.name;
    });
  }

  Future<int?> showNumberInputDialog(BuildContext context, {required String title, required int current, required int max}) async {
    final controller = TextEditingController(text: '$current');
    return showDialog<int>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '0 - $max'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(Tr.t(dCtx, 'Cancel', 'إلغاء'))),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null && val >= 0 && val <= max) {
                Navigator.pop(dCtx, val);
              }
            },
            child: Text(Tr.t(dCtx, 'OK', 'موافق')),
          ),
        ],
      ),
    );
  }

  void openSheet([Al? existing]) {
    final e = existing?.copy() ?? Al(
      id: (alarms.isEmpty ? 0 : alarms.map((x) => x.id).reduce(max)) + 1,
      prayer: true,
      calDuration: 0,
    );
    final lbl = TextEditingController(text: e.label);
    int offsetHours = e.mins ~/ 60;
    int offsetMinutes = e.mins % 60;
    int signChoice = e.mins == 0 ? 0 : e.sign;
    int calDurationHours = e.calDuration ~/ 60;
    int calDurationMinutes = e.calDuration % 60;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) {
          final hasValidDays = e.repeatMode != 'custom' || e.days.isNotEmpty;
          final ok = (e.sound || e.vibrate || e.notify) && hasValidDays;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      existing == null
                          ? Tr.t(ctx, 'New alarm', 'منبه جديد')
                          : Tr.t(ctx, 'Edit alarm', 'تعديل المنبه'),
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: false, label: Text(Tr.t(ctx, 'Normal time', 'وقت عادي'))),
                        ButtonSegment(value: true, label: Text(Tr.t(ctx, 'Prayer time', 'وقت الصلاة'))),
                      ],
                      selected: {e.prayer},
                      onSelectionChanged: (s) => set(() => e.prayer = s.first),
                    ),
                    const SizedBox(height: 12),
                    if (!e.prayer)
                      ListTile(
                        title: Text(
                          formatTime(DateTime(0, 1, 1, e.minutes ~/ 60, e.minutes % 60), ctx),
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w400),
                        ),
                        trailing: const Icon(Icons.access_time),
                        onTap: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay(hour: e.minutes ~/ 60, minute: e.minutes % 60),
                          );
                          if (t != null) set(() => e.minutes = t.hour * 60 + t.minute);
                        },
                      ),
                    if (e.prayer) ...[
                      DropdownButtonFormField<String>(
                        value: e.p,
                        decoration: InputDecoration(
                          labelText: Tr.t(ctx, 'Prayer', 'الصلاة'),
                          prefixIcon: const Icon(Icons.mosque),
                        ),
                        items: [
                          for (final p in prayers)
                            DropdownMenuItem(value: p, child: Text(Tr.prayer(ctx, p))),
                        ],
                        onChanged: (v) => set(() => e.p = v!),
                      ),
                      const SizedBox(height: 14),

                      Text(Tr.t(ctx, 'Alarm timing', 'توقيت التنبيه بالنسبة للصلاة'), style: Theme.of(ctx).textTheme.titleSmall),
                      const SizedBox(height: 8),

                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: -1, label: Text(Tr.t(ctx, '− Before', '− قبل'))),
                          ButtonSegment(value: 0, label: Text(Tr.t(ctx, 'At prayer', 'في الموعد'))),
                          ButtonSegment(value: 1, label: Text(Tr.t(ctx, '+ After', '+ بعد'))),
                        ],
                        selected: {signChoice},
                        onSelectionChanged: (s) {
                          set(() {
                            signChoice = s.first;
                            if (signChoice == 0) {
                              offsetHours = 0;
                              offsetMinutes = 0;
                              e.mins = 0;
                              e.sign = 1;
                            } else {
                              e.sign = signChoice;
                              if (e.mins == 0) {
                                offsetMinutes = 10;
                                e.mins = 10;
                              }
                            }
                          });
                        },
                      ),

                      if (signChoice != 0) ...[
                        const SizedBox(height: 14),

                        // Hours & Minutes Picker Card
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Hours Stepper
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(Tr.t(ctx, 'Hours', 'ساعات'), style: Theme.of(ctx).textTheme.labelMedium),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton.filledTonal(
                                        icon: const Icon(Icons.remove, size: 18),
                                        onPressed: offsetHours > 0 ? () => set(() {
                                          offsetHours--;
                                          e.mins = offsetHours * 60 + offsetMinutes;
                                        }) : null,
                                      ),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () async {
                                          final val = await showNumberInputDialog(ctx, title: Tr.t(ctx, 'Hours', 'ساعات'), current: offsetHours, max: 12);
                                          if (val != null) set(() { offsetHours = val; e.mins = offsetHours * 60 + offsetMinutes; });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          child: Text(
                                            '$offsetHours',
                                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                      IconButton.filledTonal(
                                        icon: const Icon(Icons.add, size: 18),
                                        onPressed: offsetHours < 12 ? () => set(() {
                                          offsetHours++;
                                          e.mins = offsetHours * 60 + offsetMinutes;
                                        }) : null,
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.outline)),
                              ),

                              // Minutes Stepper
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(Tr.t(ctx, 'Minutes', 'دقائق'), style: Theme.of(ctx).textTheme.labelMedium),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton.filledTonal(
                                        icon: const Icon(Icons.remove, size: 18),
                                        onPressed: (offsetMinutes > 0 || offsetHours > 0) ? () => set(() {
                                          if (offsetMinutes > 0) {
                                            offsetMinutes--;
                                          } else if (offsetHours > 0) {
                                            offsetHours--;
                                            offsetMinutes = 59;
                                          }
                                          e.mins = offsetHours * 60 + offsetMinutes;
                                        }) : null,
                                      ),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () async {
                                          final val = await showNumberInputDialog(ctx, title: Tr.t(ctx, 'Minutes', 'دقائق'), current: offsetMinutes, max: 59);
                                          if (val != null) set(() { offsetMinutes = val; e.mins = offsetHours * 60 + offsetMinutes; });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          child: Text(
                                            offsetMinutes.toString().padLeft(2, '0'),
                                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                      IconButton.filledTonal(
                                        icon: const Icon(Icons.add, size: 18),
                                        onPressed: () => set(() {
                                          if (offsetMinutes < 59) {
                                            offsetMinutes++;
                                          } else if (offsetHours < 12) {
                                            offsetHours++;
                                            offsetMinutes = 0;
                                          }
                                          e.mins = offsetHours * 60 + offsetMinutes;
                                        }),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Live calculation preview
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.primaryContainer.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_filled, size: 18, color: Theme.of(ctx).colorScheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${Tr.t(ctx, "Rings today at ", "سيرن اليوم في ")}${formatTime(ringAt(e, DateTime.now()), ctx)} (${e.desc(ctx)})',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: lbl,
                      decoration: InputDecoration(labelText: Tr.t(ctx, 'Label (optional)', 'التسمية (اختياري)')),
                    ),
                    const SizedBox(height: 14),

                    // =========================================================
                    // REPEAT OPTIONS: Only once (default), Every day, Specific days
                    // =========================================================
                    Text(Tr.t(ctx, 'Repeat', 'التكرار'), style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'once', label: Text(Tr.t(ctx, 'Only once', 'مرة واحدة'))),
                        ButtonSegment(value: 'daily', label: Text(Tr.t(ctx, 'Every day', 'كل يوم'))),
                        ButtonSegment(value: 'custom', label: Text(Tr.t(ctx, 'Specific days', 'أيام محددة'))),
                      ],
                      selected: {e.repeatMode},
                      onSelectionChanged: (s) => set(() => e.repeatMode = s.first),
                    ),
                    if (e.repeatMode == 'custom') ...[
                      const SizedBox(height: 10),

                      // Quick preset buttons
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              label: Text(Tr.t(ctx, 'Weekdays', 'أيام العمل')),
                              avatar: const Icon(Icons.work_outline, size: 14),
                              onPressed: () => set(() {
                                e.days = Tr.isAr(ctx)
                                    ? [DateTime.sunday, DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday]
                                    : [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday];
                              }),
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              label: Text(Tr.t(ctx, 'Weekend', 'عطلة الأسبوع')),
                              avatar: const Icon(Icons.weekend_outlined, size: 14),
                              onPressed: () => set(() {
                                e.days = Tr.isAr(ctx)
                                    ? [DateTime.friday, DateTime.saturday]
                                    : [DateTime.saturday, DateTime.sunday];
                              }),
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              label: Text(Tr.t(ctx, 'All', 'الكل')),
                              avatar: const Icon(Icons.done_all, size: 14),
                              onPressed: () => set(() {
                                e.days = [1, 2, 3, 4, 5, 6, 7];
                              }),
                            ),
                            const SizedBox(width: 6),
                            ActionChip(
                              label: Text(Tr.t(ctx, 'Clear', 'مسح')),
                              avatar: const Icon(Icons.clear, size: 14),
                              onPressed: () => set(() {
                                e.days.clear();
                              }),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Circular 7-day row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final item in (Tr.isAr(ctx) ? weekDaysAr : weekDaysEn)) ...[
                              Builder(
                                builder: (_) {
                                  final day = item['day'] as int;
                                  final isSelected = e.days.contains(day);
                                  final label = item['short'] as String;
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: Material(
                                        color: isSelected
                                            ? Theme.of(ctx).colorScheme.primary
                                            : Theme.of(ctx).colorScheme.surfaceContainerHighest,
                                        shape: const CircleBorder(),
                                        elevation: isSelected ? 2 : 0,
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () => set(() {
                                            if (isSelected) {
                                              e.days.remove(day);
                                            } else {
                                              e.days.add(day);
                                            }
                                          }),
                                          child: SizedBox(
                                            height: 44,
                                            child: Center(
                                              child: Text(
                                                label,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: Tr.isAr(ctx) ? 12 : 13,
                                                  color: isSelected
                                                      ? Theme.of(ctx).colorScheme.onPrimary
                                                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Summary or Error
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                        child: e.days.isEmpty
                            ? Text(
                                Tr.t(ctx, 'Please select at least one day', 'يرجى اختيار يوم واحد على الأقل'),
                                style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
                              )
                            : Text(
                                '${Tr.t(ctx, "Repeats: ", "التكرار: ")}${e.repeatText(ctx)}',
                                style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    Text(Tr.t(ctx, 'What should the alarm do?', 'ماذا يفعل المنبه عند الرنين؟'), style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: Text(Tr.t(ctx, 'Ring', 'رنين')),
                          selected: e.sound,
                          onSelected: (v) => set(() => e.sound = v),
                        ),
                        FilterChip(
                          label: Text(Tr.t(ctx, 'Vibrate', 'اهتزاز')),
                          selected: e.vibrate,
                          onSelected: (v) => set(() => e.vibrate = v),
                        ),
                        FilterChip(
                          label: Text(Tr.t(ctx, 'Notification', 'إشعار')),
                          selected: e.notify,
                          onSelected: (v) => set(() => e.notify = v),
                        ),
                      ],
                    ),
                    if (!ok)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          Tr.t(ctx, 'Choose at least one action and valid days', 'اختر إجراءً واحداً على الأقل وحدد الأيام'),
                          style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                        ),
                      ),
                    if (e.sound)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.music_note),
                        title: Text(e.soundName ?? Tr.t(ctx, 'Default sound', 'النغمة الافتراضية')),
                        subtitle: Text(Tr.t(ctx, 'Tap to choose audio from your device', 'اضغط لاختيار ملف صوتي من الجهاز')),
                        trailing: e.soundPath == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => set(() {
                                  e.soundPath = null;
                                  e.soundName = null;
                                }),
                              ),
                        onTap: () => pickSound(e, set),
                      ),
                    // =========================================================
                    // CALENDAR INTEGRATION
                    // =========================================================
                    const SizedBox(height: 14),
                    Text(Tr.t(ctx, 'Calendar', 'التقويم'), style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(Tr.t(ctx, 'Add to Calendar', 'إضافة للتقويم')),
                      subtitle: Text(Tr.t(
                        ctx,
                        'Create events in your device calendar',
                        'إنشاء أحداث في تقويم الجهاز',
                      )),
                      secondary: const Icon(Icons.calendar_month),
                      value: e.addToCalendar,
                      onChanged: (v) async {
                        if (v && (_availableCalendars == null || _availableCalendars!.isEmpty)) {
                          await _refreshCalendars();
                        }
                        set(() => e.addToCalendar = v);
                      },
                    ),
                    if (e.addToCalendar) ...[
                      const SizedBox(height: 10),
                      Text(
                        Tr.t(ctx, 'Event duration', 'مدة الحدث'),
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),

                      // Hours & Minutes Picker Card for Calendar Duration
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Hours Stepper
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(Tr.t(ctx, 'Hours', 'ساعات'), style: Theme.of(ctx).textTheme.labelMedium),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.filledTonal(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: calDurationHours > 0 ? () => set(() {
                                        calDurationHours--;
                                        e.calDuration = calDurationHours * 60 + calDurationMinutes;
                                      }) : null,
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () async {
                                        final val = await showNumberInputDialog(ctx, title: Tr.t(ctx, 'Hours', 'ساعات'), current: calDurationHours, max: 24);
                                        if (val != null) set(() {
                                          calDurationHours = val;
                                          e.calDuration = calDurationHours * 60 + calDurationMinutes;
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        child: Text(
                                          '$calDurationHours',
                                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    IconButton.filledTonal(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: calDurationHours < 24 ? () => set(() {
                                        calDurationHours++;
                                        e.calDuration = calDurationHours * 60 + calDurationMinutes;
                                      }) : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.outline)),
                            ),

                            // Minutes Stepper
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(Tr.t(ctx, 'Minutes', 'دقائق'), style: Theme.of(ctx).textTheme.labelMedium),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton.filledTonal(
                                      icon: const Icon(Icons.remove, size: 18),
                                      onPressed: (calDurationMinutes > 0 || calDurationHours > 0) ? () => set(() {
                                        if (calDurationMinutes > 0) {
                                          calDurationMinutes--;
                                        } else if (calDurationHours > 0) {
                                          calDurationHours--;
                                          calDurationMinutes = 59;
                                        }
                                        e.calDuration = calDurationHours * 60 + calDurationMinutes;
                                      }) : null,
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () async {
                                        final val = await showNumberInputDialog(ctx, title: Tr.t(ctx, 'Minutes', 'دقائق'), current: calDurationMinutes, max: 59);
                                        if (val != null) set(() {
                                          calDurationMinutes = val;
                                          e.calDuration = calDurationHours * 60 + calDurationMinutes;
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        child: Text(
                                          calDurationMinutes.toString().padLeft(2, '0'),
                                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    IconButton.filledTonal(
                                      icon: const Icon(Icons.add, size: 18),
                                      onPressed: () => set(() {
                                        if (calDurationMinutes < 59) {
                                          calDurationMinutes++;
                                        } else if (calDurationHours < 24) {
                                          calDurationHours++;
                                          calDurationMinutes = 0;
                                        }
                                        e.calDuration = calDurationHours * 60 + calDurationMinutes;
                                      }),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Live duration preview
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8, bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.primaryContainer.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timelapse, size: 18, color: Theme.of(ctx).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '${Tr.t(ctx, "Event duration: ", "مدة الحدث: ")}${formatCalDuration(ctx, calDurationHours * 60 + calDurationMinutes)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Schedule ahead for (Calendar horizon per alarm)
                      const SizedBox(height: 4),
                      DropdownButtonFormField<int?>(
                        value: e.calHorizonDays,
                        decoration: InputDecoration(
                          labelText: Tr.t(ctx, 'Schedule ahead for', 'إضافة للتقويم مسبقاً لمدة'),
                          prefixIcon: const Icon(Icons.date_range),
                          helperText: Tr.t(
                            ctx,
                            'Precalculates prayer times for this period in your calendar',
                            'يقوم بحساب مواقيت الصلاة مسبقاً وتدوينها في التقويم لهذه المدة',
                          ),
                          helperMaxLines: 2,
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(Tr.t(
                              ctx,
                              'App default (${st.calendarHorizonDays} days)',
                              'الافتراضي العام (${st.calendarHorizonDays} يوماً)',
                            )),
                          ),
                          DropdownMenuItem<int?>(
                            value: 14,
                            child: Text(Tr.t(ctx, '14 days (2 weeks)', '14 يوماً (أسبوعان)')),
                          ),
                          DropdownMenuItem<int?>(
                            value: 30,
                            child: Text(Tr.t(ctx, '30 days (1 month)', '30 يوماً (شهر)')),
                          ),
                          DropdownMenuItem<int?>(
                            value: 60,
                            child: Text(Tr.t(ctx, '60 days (2 months)', '60 يوماً (شهران)')),
                          ),
                          DropdownMenuItem<int?>(
                            value: 90,
                            child: Text(Tr.t(ctx, '90 days (3 months)', '90 يوماً (3 أشهر)')),
                          ),
                          DropdownMenuItem<int?>(
                            value: 180,
                            child: Text(Tr.t(ctx, '180 days (6 months)', '180 يوماً (6 أشهر)')),
                          ),
                          DropdownMenuItem<int?>(
                            value: 365,
                            child: Text(Tr.t(ctx, '365 days (1 year)', '365 يوماً (سنة كاملة)')),
                          ),
                        ],
                        onChanged: (v) => set(() => e.calHorizonDays = v),
                      ),
                      const SizedBox(height: 10),
                      if (_availableCalendars != null && _availableCalendars!.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: (e.calendarId != null && _availableCalendars!.any((c) => c.id == e.calendarId))
                              ? e.calendarId
                              : ((st.defaultCalendarId != null && _availableCalendars!.any((c) => c.id == st.defaultCalendarId))
                                  ? st.defaultCalendarId
                                  : _availableCalendars!.first.id),
                          decoration: InputDecoration(
                            labelText: Tr.t(ctx, 'Calendar for this alarm', 'التقويم لهذا المنبه'),
                            prefixIcon: const Icon(Icons.event_note),
                            helperText: Tr.t(ctx, 'Override the default calendar', 'تجاوز التقويم الافتراضي'),
                          ),
                          items: [
                            for (final cal in _availableCalendars!)
                              DropdownMenuItem(
                                value: cal.id,
                                child: Text(
                                  calendarDisplayName(cal),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            set(() {
                              e.calendarId = (v == st.defaultCalendarId) ? null : v;
                            });
                          },
                        ),
                      ] else ...[
                        FutureBuilder<List<dc.Calendar>>(
                          future: CalendarService.getWritableCalendars(),
                          builder: (fbCtx, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                              );
                            }
                            final calendars = snapshot.data ?? [];
                            if (calendars.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  Tr.t(fbCtx, 'No calendar available. Check Settings > Calendar.', 'لا يوجد تقويم متاح. راجع الإعدادات > التقويم.'),
                                  style: TextStyle(color: Theme.of(fbCtx).colorScheme.error, fontSize: 12),
                                ),
                              );
                            }
                            return DropdownButtonFormField<String>(
                              value: (e.calendarId != null && calendars.any((c) => c.id == e.calendarId))
                                  ? e.calendarId
                                  : calendars.first.id,
                              decoration: InputDecoration(
                                labelText: Tr.t(fbCtx, 'Calendar for this alarm', 'التقويم لهذا المنبه'),
                                prefixIcon: const Icon(Icons.event_note),
                              ),
                              items: [
                                for (final cal in calendars)
                                  DropdownMenuItem(
                                    value: cal.id,
                                    child: Text(
                                      calendarDisplayName(cal),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                set(() {
                                  e.calendarId = (v == st.defaultCalendarId) ? null : v;
                                });
                              },
                            );
                          },
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: !ok
                            ? null
                            : () async {
                                if (e.prayer) {
                                  if (signChoice == 0) {
                                    e.mins = 0;
                                    e.sign = 1;
                                  } else {
                                    e.sign = signChoice;
                                    e.mins = offsetHours * 60 + offsetMinutes;
                                  }
                                }
                                if (e.addToCalendar) {
                                  final dur = calDurationHours * 60 + calDurationMinutes;
                                  e.calDuration = dur >= 0 ? dur : 0;
                                }
                                e.label = lbl.text.trim();
                                e.on = true;
                                if (existing != null) {
                                  final i = alarms.indexOf(existing);
                                  if (i >= 0) alarms[i] = e;
                                } else {
                                  alarms.add(e);
                                }
                                save();
                                await reschedule();
                                // Fire-and-forget calendar sync
                                if (e.addToCalendar) {
                                  CalendarService.syncAlarmToCalendar(e).then((_) => save());
                                } else if (e.calEventIds.isNotEmpty) {
                                  CalendarService.removeAlarmFromCalendar(e).then((_) => save());
                                }
                                if (mounted) {
                                  setState(() {});
                                  Navigator.pop(ctx);
                                }
                              },
                        child: Text(Tr.t(ctx, 'Save alarm', 'حفظ المنبه')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
