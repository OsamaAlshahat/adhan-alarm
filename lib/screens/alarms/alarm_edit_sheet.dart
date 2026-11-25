import 'dart:io';
import 'dart:math';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/ar.dart';
import '../../core/localization/en.dart';
import '../../core/localization/tr.dart';
import '../../core/utils/date_time_utils.dart';
import '../../models/alarm_model.dart';
import '../../services/alarm_service.dart';
import '../../services/calendar_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/holdable_icon_button.dart';
import '../../widgets/number_input_dialog.dart';

Future<void> showAlarmEditSheet(
  BuildContext context, {
  Al? existing,
  List<dc.Calendar>? availableCalendars,
  Future<void> Function()? refreshCalendars,
  required VoidCallback onSaved,
}) {
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

  Future<void> pickSound(Al alarm, void Function(void Function()) set) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final ext = f.name.contains('.') ? f.name.substring(f.name.lastIndexOf('.')) : '.mp3';
    final dest = '${dir.path}/sound_${alarm.id}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(f.path!).copy(dest);
    set(() {
      alarm.soundPath = dest;
      alarm.soundName = f.name;
    });
  }

  return showModalBottomSheet(
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
                                    HoldableIconButton(
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
                                    HoldableIconButton(
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
                                    HoldableIconButton(
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
                                    HoldableIconButton(
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
                      if (v && (availableCalendars == null || availableCalendars.isEmpty)) {
                        await refreshCalendars?.call();
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
                                  HoldableIconButton(
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
                                  HoldableIconButton(
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
                                  HoldableIconButton(
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
                                  HoldableIconButton(
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
                    if (e.repeatMode == 'once') ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Theme.of(ctx).colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                Tr.t(
                                  ctx,
                                  'One-time alarm: A single event will be added to the calendar for this alarm date.',
                                  'منبه لمرة واحدة: سيتم إنشاء حدث واحد فقط في التقويم في موعد هذا المنبه.',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        Tr.t(ctx, 'Schedule ahead for', 'إضافة للتقويم مسبقاً لمدة'),
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: false,
                            label: Text(
                              '${Tr.t(ctx, "App default", "الافتراضي العام")} (${st.calendarHorizonDays} ${Tr.t(ctx, "days", "يوم")})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text(
                              Tr.t(ctx, 'Custom days', 'تحديد مخصص'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                        selected: {e.calHorizonDays != null},
                        onSelectionChanged: (s) {
                          set(() {
                            if (s.first) {
                              e.calHorizonDays = e.calHorizonDays ?? st.calendarHorizonDays;
                            } else {
                              e.calHorizonDays = null;
                            }
                          });
                        },
                      ),
                      if (e.calHorizonDays != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                Tr.t(ctx, 'Days ahead', 'عدد الأيام مسبقاً'),
                                style: Theme.of(ctx).textTheme.labelLarge,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HoldableIconButton(
                                    icon: const Icon(Icons.remove, size: 18),
                                    onPressed: (e.calHorizonDays ?? st.calendarHorizonDays) > 1
                                        ? () => set(() {
                                            final cur = e.calHorizonDays ?? st.calendarHorizonDays;
                                            if (cur > 1) e.calHorizonDays = cur - 1;
                                          })
                                        : null,
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () async {
                                      final val = await showNumberInputDialog(
                                        ctx,
                                        title: Tr.t(ctx, 'Schedule ahead for (days)', 'إضافة للتقويم مسبقاً لمدة (أيام)'),
                                        current: e.calHorizonDays ?? st.calendarHorizonDays,
                                        min: 1,
                                        max: 365,
                                      );
                                      if (val != null) set(() => e.calHorizonDays = val);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                      child: Text(
                                        '${e.calHorizonDays ?? st.calendarHorizonDays} ${Tr.t(ctx, "days", "يوم")}',
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                  HoldableIconButton(
                                    icon: const Icon(Icons.add, size: 18),
                                    onPressed: (e.calHorizonDays ?? st.calendarHorizonDays) < 365
                                        ? () => set(() {
                                            final cur = e.calHorizonDays ?? st.calendarHorizonDays;
                                            if (cur < 365) e.calHorizonDays = cur + 1;
                                          })
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final d in [7, 14, 30, 60, 90, 180, 365]) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text('$d ${Tr.t(ctx, "days", "يوم")}'),
                                    selected: e.calHorizonDays == d,
                                    onSelected: (sel) {
                                      if (sel) set(() => e.calHorizonDays = d);
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    if (availableCalendars != null && availableCalendars.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: (e.calendarId != null && availableCalendars.any((c) => c.id == e.calendarId))
                            ? e.calendarId
                            : ((st.defaultCalendarId != null && availableCalendars.any((c) => c.id == st.defaultCalendarId))
                                ? st.defaultCalendarId
                                : availableCalendars.first.id),
                        decoration: InputDecoration(
                          labelText: Tr.t(ctx, 'Calendar for this alarm', 'التقويم لهذا المنبه'),
                          prefixIcon: const Icon(Icons.event_note),
                          helperText: Tr.t(ctx, 'Override the default calendar', 'تجاوز التقويم الافتراضي'),
                        ),
                        items: [
                          for (final cal in availableCalendars)
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
                              final oldCalendarId = existing?.calendarId;
                              final wasInCalendar = existing?.addToCalendar == true;

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
                              // Sync calendar events
                              if (e.addToCalendar) {
                                CalendarService.syncAlarmToCalendar(e, oldCalendarId: oldCalendarId).then((_) => save());
                              } else if (wasInCalendar || e.calEventIds.isNotEmpty) {
                                CalendarService.removeAlarmFromCalendar(e).then((_) => save());
                              }
                              onSaved();
                              Navigator.pop(ctx);
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

