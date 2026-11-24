import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/tr.dart';
import '../../core/utils/date_time_utils.dart';
import '../../models/alarm_model.dart';
import '../../services/alarm_service.dart';
import '../../services/calendar_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';

class AlarmsView extends StatefulWidget {
  final void Function([Al? existing]) onEditAlarm;

  const AlarmsView({super.key, required this.onEditAlarm});

  @override
  State<AlarmsView> createState() => _AlarmsViewState();
}

class _AlarmsViewState extends State<AlarmsView> {
  String _alarmFilter = 'all'; // 'all', 'calendar', 'normal'

  @override
  Widget build(BuildContext context) {
    final t = timesFor(DateTime.now());
    final filteredAlarms = alarms.where((a) {
      if (_alarmFilter == 'calendar') return a.addToCalendar;
      if (_alarmFilter == 'normal') return !a.addToCalendar;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Prayer Times Carousel Card
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

        // Filter Bar (All / Calendar / Normal)
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
              onTap: () => widget.onEditAlarm(a),
              title: Row(
                children: [
                  Text(
                    formatTime(ringAt(a, DateTime.now()), context),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
                  ),
                  if (a.addToCalendar) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.calendar_month,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
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
}

