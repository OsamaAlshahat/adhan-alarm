import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:adhan/adhan.dart';
import 'package:alarm/alarm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}

class Settings {
  String country = 'Egypt', city = 'Alexandria', method = 'egyptian';
  double lat = 31.2, lng = 29.92;
  String timeFormat = 'system'; // 'system', '12h', '24h'
  String language = 'system';   // 'system', 'en', 'ar'

  Map<String, dynamic> toJson() => {
    'country': country,
    'city': city,
    'method': method,
    'lat': lat,
    'lng': lng,
    'timeFormat': timeFormat,
    'language': language,
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

  Al({
    required this.id,
    this.prayer = false,
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
  }) : days = days ?? [DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday];

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
  };

  factory Al.from(Map<String, dynamic> j) {
    final mode = j['repeatMode'] as String? ?? (j['once'] == false ? 'daily' : 'once');
    final rawDays = j['days'] as List?;
    final parsedDays = rawDays != null
        ? rawDays.map((e) => (e as num).toInt()).toList()
        : <int>[DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday];

    return Al(
      id: j['id'],
      prayer: j['prayer'] ?? false,
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
    final rel = sign < 0 ? (ar ? 'قبل' : 'before') : (ar ? 'بعد' : 'after');
    return ar ? '$rel $pName بـ $mins دقيقة' : '$mins min $rel $pName';
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

/// Prayer times change every day, so we pre-schedule the next 14 days as exact
/// OS-level alarms. This runs on every app open and every change.
Future<void> reschedule() async {
  final now = DateTime.now();
  for (final s in await Alarm.getAlarms()) {
    if (s.dateTime.isAfter(now)) await Alarm.stop(s.id);
  }
  for (final a in alarms.where((a) => a.on)) {
    final path = (a.soundPath != null && File(a.soundPath!).existsSync()) ? a.soundPath! : 'assets/alarm.wav';
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
      await Alarm.set(alarmSettings: AlarmSettings(
        id: a.id * 100 + i,
        dateTime: at,
        assetAudioPath: path,
        loopAudio: true,
        vibrate: a.vibrate,
        androidFullScreenIntent: true,
        warningNotificationOnKill: a.notify,
        volumeSettings: VolumeSettings.fixed(volume: a.sound ? 0.9 : 0.0, volumeEnforced: a.sound),
        notificationSettings: NotificationSettings(
          title: a.notify ? titleText : '',
          body: a.notify ? formatTime(at) : '',
          stopButton: a.notify ? 'Stop' : null,
        ),
      ));

      // 'once' mode only schedules the first upcoming occurrence
      if (a.repeatMode == 'once' && ++count == 1) break;
    }
  }
}

final navKey = GlobalKey<NavigatorState>();
final ringing = <int>{};
VoidCallback? homeRefresh;

void showRing(AlarmSettings s) {
  if (ringing.contains(s.id)) return;
  ringing.add(s.id);
  final a = alarms.where((x) => x.id == s.id ~/ 100).firstOrNull;
  if (a != null && a.repeatMode == 'once') {
    a.on = false;
    save();
  }
  navKey.currentState?.push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => RingScreen(s, a),
  )).then((_) {
    ringing.remove(s.id);
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
        backgroundColor: cs.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.alarm, size: 80, color: cs.onPrimary),
                const SizedBox(height: 12),
                Text(
                  formatTime(s.dateTime, c),
                  style: TextStyle(fontSize: 64, fontWeight: FontWeight.w300, color: cs.onPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, color: cs.onPrimary),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: FilledButton.tonal(
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
                      backgroundColor: cs.onPrimary,
                      foregroundColor: cs.primary,
                    ),
                    onPressed: () async {
                      await Alarm.stop(s.id);
                      nav.pop();
                    },
                    child: Text(Tr.t(c, 'Stop', 'إيقاف'), style: const TextStyle(fontSize: 20)),
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
  }

  await reschedule();

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
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.not_required,
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
          title: 'Adhan Alarm',
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
            colorSchemeSeed: const Color(0xFF0F6B57),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF0F6B57),
            brightness: Brightness.dark,
            useMaterial3: true,
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

class _H extends State<Home> {
  int tab = 0;
  StreamSubscription<AlarmSettings>? sub;

  @override
  void initState() {
    super.initState();
    homeRefresh = () {
      if (mounted) setState(() {});
    };
    sub = Alarm.ringStream.stream.listen(showRing);
    Future.delayed(const Duration(milliseconds: 600), () async {
      final now = DateTime.now();
      for (final s in await Alarm.getAlarms()) {
        if (!s.dateTime.isAfter(now) && now.difference(s.dateTime).inMinutes < 10) {
          showRing(s);
        }
      }
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    homeRefresh = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(tab == 0 ? Tr.t(c, 'Adhan Alarm', 'منبه الأذان') : Tr.t(c, 'Settings', 'الإعدادات')),
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

  /// Header widget with placeholder app image that can easily be updated later
  Widget appHeaderWithPlaceholder(BuildContext c) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Theme.of(c).colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // =========================================================================
            // APP IMAGE PLACEHOLDER:
            // Replace 'assets/placeholder.png' with your final app logo / hero artwork.
            // =========================================================================
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/placeholder.png',
                width: 54,
                height: 54,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Theme.of(c).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.alarm, color: Theme.of(c).colorScheme.primary, size: 30),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Tr.t(c, 'Adhan Alarm', 'منبه الأذان'),
                    style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${Tr.country(c, st.country)} · ${st.city}',
                    style: Theme.of(c).textTheme.bodySmall?.copyWith(color: Theme.of(c).colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget alarmsView() {
    final t = timesFor(DateTime.now());
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        appHeaderWithPlaceholder(context),
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
        if (alarms.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                Tr.t(context, 'No alarms yet. Tap “New alarm”.', 'لا توجد منبهات حالياً. اضغط على "منبه جديد".'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        for (final a in alarms)
          Card(
            child: ListTile(
              onTap: () => openSheet(a),
              title: Text(
                formatTime(ringAt(a, DateTime.now()), context),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
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
                      setState(() {});
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
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
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: list.any((x) => x[0] == st.city) ? st.city : null,
          decoration: InputDecoration(labelText: Tr.t(context, 'City', 'المدينة'), prefixIcon: const Icon(Icons.location_city)),
          items: [
            for (final x in list)
              DropdownMenuItem(value: x[0] as String, child: Text(x[0] as String)),
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
          },
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
    m.showSnackBar(SnackBar(content: Text('${Tr.t(context, "Location set: ", "تم تحديد الموقع: ")}${st.city}')));
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

  void openSheet([Al? existing]) {
    final e = existing?.copy() ?? Al(id: (alarms.isEmpty ? 0 : alarms.map((x) => x.id).reduce(max)) + 1);
    final lbl = TextEditingController(text: e.label);
    final mins = TextEditingController(text: '${e.mins}');

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
                        decoration: InputDecoration(labelText: Tr.t(ctx, '1. Prayer', '1. الصلاة')),
                        items: [
                          for (final p in prayers)
                            DropdownMenuItem(value: p, child: Text(Tr.prayer(ctx, p))),
                        ],
                        onChanged: (v) => set(() => e.p = v!),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(value: -1, label: Text(Tr.t(ctx, '− Before', '− قبل'))),
                          ButtonSegment(value: 1, label: Text(Tr.t(ctx, '+ After', '+ بعد'))),
                        ],
                        selected: {e.sign},
                        onSelectionChanged: (s) => set(() => e.sign = s.first),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mins,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: Tr.t(ctx, '3. Minutes', '3. الدقائق')),
                        onChanged: (v) => set(() => e.mins = int.tryParse(v) ?? 0),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('${Tr.t(ctx, "Rings today at ", "سيرن اليوم في ")}${formatTime(ringAt(e, DateTime.now()), ctx)}'),
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
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final item in (Tr.isAr(ctx) ? weekDaysAr : weekDaysEn))
                            FilterChip(
                              label: Text(item['name'] as String),
                              selected: e.days.contains(item['day']),
                              onSelected: (selected) {
                                set(() {
                                  final d = item['day'] as int;
                                  if (selected) {
                                    if (!e.days.contains(d)) e.days.add(d);
                                  } else {
                                    e.days.remove(d);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      if (e.days.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            Tr.t(ctx, 'Please select at least one day', 'يرجى اختيار يوم واحد على الأقل'),
                            style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontSize: 12),
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: !ok
                            ? null
                            : () async {
                                e.mins = int.tryParse(mins.text) ?? e.mins;
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
