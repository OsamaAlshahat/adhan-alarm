import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:adhan/adhan.dart';
import 'package:alarm/alarm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const prayers = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
const prayerNames = {'fajr': 'Fajr', 'sunrise': 'Sunrise', 'dhuhr': 'Dhuhr', 'asr': 'Asr', 'maghrib': 'Maghrib', 'isha': 'Isha'};
const methods = {
  'egyptian': CalculationMethod.egyptian,
  'mwl': CalculationMethod.muslim_world_league,
  'makkah': CalculationMethod.umm_al_qura,
  'karachi': CalculationMethod.karachi,
  'isna': CalculationMethod.north_america,
};
// country -> [city, lat, lng]  (built in, so no internet is needed)
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

class Settings {
  String country = 'Egypt', city = 'Alexandria', method = 'egyptian';
  double lat = 31.2, lng = 29.92;
  Map<String, dynamic> toJson() => {'country': country, 'city': city, 'method': method, 'lat': lat, 'lng': lng};
  Settings();
  Settings.from(Map<String, dynamic> j) {
    country = j['country']; city = j['city']; method = j['method']; lat = j['lat']; lng = j['lng'];
  }
}

class Al {
  int id; bool prayer; int minutes; String p; int sign; int mins; String label; bool on; bool once;
  bool notify, vibrate, sound; String? soundPath, soundName;
  Al({required this.id, this.prayer = false, this.minutes = 420, this.p = 'fajr', this.sign = 1, this.mins = 10, this.label = '', this.on = true, this.once = false,
      this.notify = true, this.vibrate = true, this.sound = true, this.soundPath, this.soundName});
  Map<String, dynamic> toJson() => {'id': id, 'prayer': prayer, 'minutes': minutes, 'p': p, 'sign': sign, 'mins': mins, 'label': label, 'on': on, 'once': once,
        'notify': notify, 'vibrate': vibrate, 'sound': sound, 'soundPath': soundPath, 'soundName': soundName};
  factory Al.from(Map<String, dynamic> j) => Al(id: j['id'], prayer: j['prayer'], minutes: j['minutes'], p: j['p'], sign: j['sign'], mins: j['mins'], label: j['label'], on: j['on'], once: j['once'],
      notify: j['notify'] ?? true, vibrate: j['vibrate'] ?? true, sound: j['sound'] ?? true, soundPath: j['soundPath'], soundName: j['soundName']);
  Al copy() => Al.from(jsonDecode(jsonEncode(toJson())));
  String get desc => prayer ? (mins == 0 ? 'At ${prayerNames[p]}' : '$mins min ${sign < 0 ? 'before' : 'after'} ${prayerNames[p]}') : 'Normal alarm';
  String get actions => [if (sound) 'Ring', if (vibrate) 'Vibrate', if (notify) 'Notify'].join(', ');
}

late SharedPreferences prefs;
Settings st = Settings();
List<Al> alarms = [];

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
  final r = DateTime(t.year, t.month, t.day, t.hour, t.minute).add(Duration(minutes: a.sign * a.mins));
  return r;
}

String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Prayer times change every day, so we pre-schedule the next 14 days as exact
/// OS-level alarms. This runs on every app open and every change.
Future<void> reschedule() async {
  final now = DateTime.now();
  // stop only FUTURE alarms; never stop one that is ringing right now
  for (final s in await Alarm.getAlarms()) { if (s.dateTime.isAfter(now)) await Alarm.stop(s.id); }
  for (final a in alarms.where((a) => a.on)) {
    final path = (a.soundPath != null && File(a.soundPath!).existsSync()) ? a.soundPath! : 'assets/alarm.wav';
    var count = 0;
    for (var i = 0; i < 14; i++) {
      final at = ringAt(a, now.add(Duration(days: i)));
      if (!at.isAfter(now)) continue;
      await Alarm.set(alarmSettings: AlarmSettings(
        id: a.id * 100 + i,
        dateTime: at,
        assetAudioPath: path,
        loopAudio: true,
        vibrate: a.vibrate,
        androidFullScreenIntent: true,
        warningNotificationOnKill: a.notify,
        volumeSettings: VolumeSettings.fixed(volume: a.sound ? 0.9 : 0.0, volumeEnforced: a.sound),
        notificationSettings: NotificationSettings(title: a.notify ? (a.label.isEmpty ? a.desc : a.label) : '', body: a.notify ? hm(at) : '', stopButton: a.notify ? 'Stop' : null),
      ));
      if (a.once && ++count == 1) break;
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
  if (a != null && a.once) { a.on = false; save(); }
  final title = a == null ? 'Alarm' : (a.label.isEmpty ? a.desc : a.label);
  navKey.currentState?.push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => RingScreen(s, title))).then((_) { ringing.remove(s.id); homeRefresh?.call(); });
}

class RingScreen extends StatelessWidget {
  final AlarmSettings s; final String title;
  const RingScreen(this.s, this.title, {super.key});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    final nav = Navigator.of(c);
    return PopScope(canPop: false, child: Scaffold(
      backgroundColor: cs.primary,
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.alarm, size: 80, color: cs.onPrimary),
        const SizedBox(height: 12),
        Text(hm(s.dateTime), style: TextStyle(fontSize: 80, fontWeight: FontWeight.w300, color: cs.onPrimary)),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: cs.onPrimary)),
        const SizedBox(height: 48),
        SizedBox(width: double.infinity, height: 60, child: FilledButton.tonal(onPressed: () async {
          await Alarm.stop(s.id);
          await Alarm.set(alarmSettings: s.copyWith(id: 9000000 + Random().nextInt(99999), dateTime: DateTime.now().add(const Duration(minutes: 5))));
          nav.pop();
        }, child: const Text('Snooze 5 min', style: TextStyle(fontSize: 20)))),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, height: 60, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: cs.onPrimary, foregroundColor: cs.primary), onPressed: () async {
          await Alarm.stop(s.id);
          nav.pop();
        }, child: const Text('Stop', style: TextStyle(fontSize: 20)))),
      ]))),
    ));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
  final s = prefs.getString('st'); if (s != null) st = Settings.from(jsonDecode(s));
  final l = prefs.getString('al'); if (l != null) alarms = (jsonDecode(l) as List).map((e) => Al.from(e)).toList();
  await Alarm.init();
  await Permission.notification.request();
  await Permission.scheduleExactAlarm.request();
  await reschedule();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Adhan Alarm',
        navigatorKey: navKey,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0F6B57), useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF0F6B57), brightness: Brightness.dark, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState() => _H(); }

class _H extends State<Home> {
  int tab = 0;
  StreamSubscription<AlarmSettings>? sub;
  @override
  void initState() {
    super.initState();
    homeRefresh = () { if (mounted) setState(() {}); };
    sub = Alarm.ringStream.stream.listen(showRing);
    // app opened by the alarm itself: the ring event may already have fired
    Future.delayed(const Duration(milliseconds: 600), () async {
      final now = DateTime.now();
      for (final s in await Alarm.getAlarms()) {
        if (!s.dateTime.isAfter(now) && now.difference(s.dateTime).inMinutes < 10) showRing(s);
      }
    });
  }
  @override
  void dispose() { sub?.cancel(); homeRefresh = null; super.dispose(); }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(tab == 0 ? 'Adhan Alarm' : 'Settings')),
        body: SafeArea(top: false, child: tab == 0 ? alarmsView() : settingsView()),
        floatingActionButton: tab == 0 ? FloatingActionButton.extended(onPressed: () => openSheet(), icon: const Icon(Icons.add), label: const Text('New alarm')) : null,
        bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i), destinations: const [
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Alarms'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ]),
      );

  Widget alarmsView() {
    final t = timesFor(DateTime.now());
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('${st.city}, ${st.country}', style: Theme.of(context).textTheme.bodyMedium),
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (final p in prayers) Column(children: [Text(prayerNames[p]!, style: const TextStyle(fontSize: 11)), Text(hm(prayerTime(t, p)!), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
      ]))),
      if (alarms.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No alarms yet. Tap “New alarm”.')),
      for (final a in alarms) Card(child: ListTile(
        onTap: () => openSheet(a),
        title: Text(hm(ringAt(a, DateTime.now())), style: const TextStyle(fontSize: 30)),
        subtitle: Text('${a.label.isEmpty ? '' : '${a.label} · '}${a.desc} · ${a.once ? 'Once' : 'Daily'}\n${a.actions}'),
        isThreeLine: true,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: a.on, onChanged: (v) async { a.on = v; save(); await reschedule(); setState(() {}); }),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { alarms.remove(a); save(); await reschedule(); setState(() {}); }),
        ]),
      )),
      const SizedBox(height: 90),
    ]);
  }

  Widget settingsView() {
    final list = cities[st.country] ?? [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      DropdownButtonFormField<String>(value: cities.containsKey(st.country) ? st.country : null, decoration: const InputDecoration(labelText: 'Country'),
        items: [for (final k in cities.keys) DropdownMenuItem(value: k, child: Text(k))],
        onChanged: (v) { final f = cities[v]!.first; setState(() { st.country = v!; st.city = f[0] as String; st.lat = f[1] as double; st.lng = f[2] as double; }); save(); reschedule(); }),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: list.any((x) => x[0] == st.city) ? st.city : null, decoration: const InputDecoration(labelText: 'City'),
        items: [for (final x in list) DropdownMenuItem(value: x[0] as String, child: Text(x[0] as String))],
        onChanged: (v) { final x = list.firstWhere((e) => e[0] == v); setState(() { st.city = v!; st.lat = x[1] as double; st.lng = x[2] as double; }); save(); reschedule(); }),
      const SizedBox(height: 12),
      OutlinedButton.icon(icon: const Icon(Icons.my_location), label: const Text('Use GPS'), onPressed: useGps),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: st.method, decoration: const InputDecoration(labelText: 'Calculation method'), items: const [
        DropdownMenuItem(value: 'egyptian', child: Text('Egyptian General Authority')),
        DropdownMenuItem(value: 'mwl', child: Text('Muslim World League')),
        DropdownMenuItem(value: 'makkah', child: Text('Umm al-Qura (Makkah)')),
        DropdownMenuItem(value: 'karachi', child: Text('Karachi')),
        DropdownMenuItem(value: 'isna', child: Text('ISNA (North America)')),
      ], onChanged: (v) { setState(() => st.method = v!); save(); reschedule(); }),
    ]);
  }

  Future<void> useGps() async {
    final m = ScaffoldMessenger.of(context);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { m.showSnackBar(const SnackBar(content: Text('Location permission denied. Choose your city manually.'))); return; }
    final p = await Geolocator.getCurrentPosition();
    String? bc, bn; double bd = 1e9; double bl = p.latitude, bg = p.longitude;
    cities.forEach((k, l) { for (final x in l) { final d = Geolocator.distanceBetween(p.latitude, p.longitude, x[1] as double, x[2] as double) / 1000; if (d < bd) { bd = d; bc = k; bn = x[0] as String; } } });
    setState(() { st.lat = bl; st.lng = bg; st.country = bd < 150 ? bc! : 'GPS'; st.city = bd < 150 ? bn! : 'My location'; });
    save(); await reschedule();
    m.showSnackBar(SnackBar(content: Text('Location set: ${st.city}')));
  }

  Future<void> pickSound(Al e, void Function(void Function()) set) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final ext = f.name.contains('.') ? f.name.substring(f.name.lastIndexOf('.')) : '.mp3';
    final dest = '${dir.path}/sound_${e.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(f.path!).copy(dest);
    set(() { e.soundPath = dest; e.soundName = f.name; });
  }

  void openSheet([Al? existing]) {
    final e = existing?.copy() ?? Al(id: (alarms.isEmpty ? 0 : alarms.map((x) => x.id).reduce(max)) + 1);
    final lbl = TextEditingController(text: e.label), mins = TextEditingController(text: '${e.mins}');
    showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => StatefulBuilder(builder: (ctx, set) {
      final ok = e.sound || e.vibrate || e.notify;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(top: false, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(existing == null ? 'New alarm' : 'Edit alarm', style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Normal time')), ButtonSegment(value: true, label: Text('Prayer time'))], selected: {e.prayer}, onSelectionChanged: (s) => set(() => e.prayer = s.first)),
          const SizedBox(height: 12),
          if (!e.prayer) ListTile(title: Text(hm(DateTime(0, 1, 1, e.minutes ~/ 60, e.minutes % 60)), style: const TextStyle(fontSize: 32)), trailing: const Icon(Icons.access_time),
            onTap: () async { final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: e.minutes ~/ 60, minute: e.minutes % 60)); if (t != null) set(() => e.minutes = t.hour * 60 + t.minute); }),
          if (e.prayer) ...[
            DropdownButtonFormField<String>(value: e.p, decoration: const InputDecoration(labelText: '1. Prayer'), items: [for (final p in prayers) DropdownMenuItem(value: p, child: Text(prayerNames[p]!))], onChanged: (v) => set(() => e.p = v!)),
            const SizedBox(height: 12),
            SegmentedButton<int>(segments: const [ButtonSegment(value: -1, label: Text('− Before')), ButtonSegment(value: 1, label: Text('+ After'))], selected: {e.sign}, onSelectionChanged: (s) => set(() => e.sign = s.first)),
            const SizedBox(height: 12),
            TextField(controller: mins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '3. Minutes'), onChanged: (v) => set(() => e.mins = int.tryParse(v) ?? 0)),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Rings today at ${hm(ringAt(e, DateTime.now()))}')),
          ],
          TextField(controller: lbl, decoration: const InputDecoration(labelText: 'Label (optional)')),
          const SizedBox(height: 12),
          Text('What should the alarm do?', style: Theme.of(ctx).textTheme.titleSmall),
          Wrap(spacing: 8, children: [
            FilterChip(label: const Text('Ring'), selected: e.sound, onSelected: (v) => set(() => e.sound = v)),
            FilterChip(label: const Text('Vibrate'), selected: e.vibrate, onSelected: (v) => set(() => e.vibrate = v)),
            FilterChip(label: const Text('Notification'), selected: e.notify, onSelected: (v) => set(() => e.notify = v)),
          ]),
          if (!ok) Text('Choose at least one action', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          if (e.sound) ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note),
            title: Text(e.soundName ?? 'Default sound'),
            subtitle: const Text('Tap to choose audio from your device'),
            trailing: e.soundPath == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => set(() { e.soundPath = null; e.soundName = null; })),
            onTap: () => pickSound(e, set),
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Repeat every day'), value: !e.once, onChanged: (v) => set(() => e.once = !v)),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: !ok ? null : () async {
            e.mins = int.tryParse(mins.text) ?? e.mins; e.label = lbl.text.trim(); e.on = true;
            if (existing != null) { final i = alarms.indexOf(existing); if (i >= 0) alarms[i] = e; } else { alarms.add(e); }
            save(); await reschedule();
            if (mounted) { setState(() {}); Navigator.pop(ctx); }
          }, child: const Text('Save alarm'))),
        ]))),
      );
    }));
  }
}
