import 'dart:async';
import 'package:alarm/alarm.dart';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/material.dart';
import '../core/localization/tr.dart';
import '../models/alarm_model.dart';
import '../services/alarm_service.dart';
import '../services/calendar_service.dart';
import '../services/storage_service.dart';
import 'alarms/alarm_edit_sheet.dart';
import 'alarms/alarms_view.dart';
import 'settings/settings_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<AlarmSettings>? _alarmSub;
  List<dc.Calendar>? _availableCalendars;
  bool _loadingCalendars = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    homeRefresh = () {
      if (mounted) setState(() {});
    };

    _alarmSub = Alarm.ringStream.stream.listen((s) {
      showRing(s);
    });

    _refreshCalendars();

    // Check if an alarm is already ringing on launch
    Alarm.getAlarms().then((all) async {
      for (final a in all) {
        if (await Alarm.isRinging(a.id)) {
          showRing(a);
          break;
        }
      }
    });
  }

  Future<void> _refreshCalendars() async {
    if (_loadingCalendars) return;
    setState(() => _loadingCalendars = true);
    try {
      final cals = await CalendarService.getWritableCalendars();
      if (mounted) {
        setState(() {
          _availableCalendars = cals;
          _loadingCalendars = false;
          if (st.defaultCalendarId == null && cals.isNotEmpty) {
            st.defaultCalendarId = cals.first.id;
            save();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCalendars = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      reschedule();
      syncAllCalendarEvents();
      _refreshCalendars();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmSub?.cancel();
    if (homeRefresh == () => setState(() {})) {
      homeRefresh = null;
    }
    super.dispose();
  }

  void _openEditSheet([Al? existing]) {
    showAlarmEditSheet(
      context,
      existing: existing,
      availableCalendars: _availableCalendars,
      refreshCalendars: _refreshCalendars,
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? Tr.t(context, 'Alarms', 'المنبهات') : Tr.t(context, 'Settings', 'الإعدادات')),
      ),
      body: _tab == 0
          ? AlarmsView(onEditAlarm: _openEditSheet)
          : SettingsView(
              availableCalendars: _availableCalendars,
              loadingCalendars: _loadingCalendars,
              onRefreshCalendars: _refreshCalendars,
            ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openEditSheet(),
              icon: const Icon(Icons.add),
              label: Text(Tr.t(context, 'New alarm', 'منبه جديد')),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.alarm),
            label: Tr.t(context, 'Alarms', 'المنبهات'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: Tr.t(context, 'Settings', 'الإعدادات'),
          ),
        ],
      ),
    );
  }
}
