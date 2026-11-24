import 'dart:math';
import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import '../core/localization/tr.dart';
import '../core/utils/date_time_utils.dart';
import '../models/alarm_model.dart';

class RingScreen extends StatelessWidget {
  final AlarmSettings s;
  final Al? a;
  const RingScreen(this.s, this.a, {super.key});

  @override
  Widget build(BuildContext c) {
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
