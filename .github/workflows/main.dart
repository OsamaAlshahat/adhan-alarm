import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:adhan/adhan.dart';
import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
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
  Al({required this.id, this.prayer = false, this.minutes = 420, this.p = 'fajr', this.sign = 1, this.mins = 0, this.label = '', this.on = true, this.once = false});
  Map<String, dynamic> toJson() => {'id': id, 'prayer': prayer, 'minutes': minutes, 'p': p, 'sign': sign, 'mins': mins, 'label': label, 'on': on, 'once': once};
  factory Al.from(Map<String, dynamic> j) => Al(id: j['id'], prayer: j['prayer'], minutes: j['minutes'], p: j['p'], sign: j['sign'], mins: j['mins'], label: j['label'], on: j['on'], once: j['once']);
  String get desc => prayer ? (mins == 0 ? 'At ${prayerNames[p]}' : '$mins min ${sign < 0 ? 'before' : 'after'} ${prayerNames[p]}') : 'Normal alarm';
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
  await Alarm.stopAll();
  final now = DateTime.now();
  for (final a in alarms.where((a) => a.on)) {
    var count = 0;
    for (var i = 0; i < 14; i++) {
      final at = ringAt(a, now.add(Duration(days: i)));
      if (!at.isAfter(now)) continue;
      await Alarm.set(alarmSettings: AlarmSettings(
        id: a.id * 100 + i,
        dateTime: at,
        assetAudioPath: 'assets/alarm.wav',
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        warningNotificationOnKill: true,
        volumeSettings: VolumeSettings.fixed(volume: 0.9, volumeEnforced: true),
        notificationSettings: NotificationSettings(title: a.label.isEmpty ? a.desc : a.label, body: hm(at), stopButton: 'Stop'),
      ));
      if (a.once && ++count == 1) break;
    }
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
    sub = Alarm.ringStream.stream.listen(onRing);
    Alarm.getAlarms().then((l) { final r = l.where((a) => a.dateTime.isBefore(DateTime.now()) ).toList(); if (r.isNotEmpty) onRing(r.first); });
  }
  @override
  void dispose() { sub?.cancel(); super.dispose(); }

  void onRing(AlarmSettings s) {
    final a = alarms.where((x) => x.id == s.id ~/ 100).firstOrNull;
    if (a != null && a.once) { a.on = false; save(); setState(() {}); }
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      title: Text(s.notificationSettings.title),
      content: Text(hm(s.dateTime), style: Theme.of(context).textTheme.displayMedium),
      actions: [
        TextButton(onPressed: () async {
          await Alarm.stop(s.id);
          await Alarm.set(alarmSettings: s.copyWith(id: 9000000 + Random().nextInt(99999), dateTime: DateTime.now().add(const Duration(minutes: 5))));
          if (mounted) Navigator.pop(context);
        }, child: const Text('Snooze 5 min')),
        FilledButton(onPressed: () async { await Alarm.stop(s.id); if (mounted) Navigator.pop(context); }, child: const Text('Stop')),
      ],
    ));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: Text(tab == 0 ? 'Adhan Alarm' : 'Settings')),
        body: tab == 0 ? alarmsView() : settingsView(),
        floatingActionButton: tab == 0 ? FloatingActionButton.extended(onPressed: addSheet, icon: const Icon(Icons.add), label: const Text('New alarm')) : null,
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
        title: Text(hm(ringAt(a, DateTime.now())), style: const TextStyle(fontSize: 30)),
        subtitle: Text('${a.label.isEmpty ? '' : '${a.label} · '}${a.desc} · ${a.once ? 'Once' : 'Daily'}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Switch(value: a.on, onChanged: (v) async { a.on = v; save(); await reschedule(); setState(() {}); }),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { alarms.remove(a); save(); await reschedule(); setState(() {}); }),
        ]),
      )),
      const SizedBox(height: 80),
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

  void addSheet() {
    final a = Al(id: (alarms.isEmpty ? 0 : alarms.map((e) => e.id).reduce(max)) + 1);
    final lbl = TextEditingController(), mins = TextEditingController(text: '10');
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Normal time')), ButtonSegment(value: true, label: Text('Prayer time'))], selected: {a.prayer}, onSelectionChanged: (s) => set(() => a.prayer = s.first)),
        const SizedBox(height: 12),
        if (!a.prayer) ListTile(title: Text(hm(DateTime(0, 1, 1, a.minutes ~/ 60, a.minutes % 60)), style: const TextStyle(fontSize: 32)), trailing: const Icon(Icons.access_time),
          onTap: () async { final t = await showTimePicker(context: ctx, initialTime: TimeOfDay(hour: a.minutes ~/ 60, minute: a.minutes % 60)); if (t != null) set(() => a.minutes = t.hour * 60 + t.minute); }),
        if (a.prayer) ...[
          DropdownButtonFormField<String>(value: a.p, decoration: const InputDecoration(labelText: '1. Prayer'), items: [for (final p in prayers) DropdownMenuItem(value: p, child: Text(prayerNames[p]!))], onChanged: (v) => set(() => a.p = v!)),
          const SizedBox(height: 12),
          SegmentedButton<int>(segments: const [ButtonSegment(value: -1, label: Text('− Before')), ButtonSegment(value: 1, label: Text('+ After'))], selected: {a.sign}, onSelectionChanged: (s) => set(() => a.sign = s.first)),
          const SizedBox(height: 12),
          TextField(controller: mins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '3. Minutes'), onChanged: (v) => set(() => a.mins = int.tryParse(v) ?? 0)),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text('Rings today at ${hm(ringAt(a..mins = int.tryParse(mins.text) ?? 0, DateTime.now()))}')),
        ],
        TextField(controller: lbl, decoration: const InputDecoration(labelText: 'Label (optional)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Repeat every day'), value: !a.once, onChanged: (v) => set(() => a.once = !v)),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () async {
          a.mins = int.tryParse(mins.text) ?? 0; a.label = lbl.text.trim();
          alarms.add(a); save(); await reschedule(); if (mounted) { setState(() {}); Navigator.pop(ctx); }
        }, child: const Text('Save alarm'))),
      ])),
    )));
  }
}
