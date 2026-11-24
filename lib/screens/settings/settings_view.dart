import 'dart:io';
import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/tr.dart';
import '../../core/utils/platform_utils.dart';
import '../../services/alarm_service.dart';
import '../../services/calendar_service.dart';
import '../../services/storage_service.dart';

class SettingsView extends StatefulWidget {
  final List<dc.Calendar>? availableCalendars;
  final bool loadingCalendars;
  final Future<void> Function() onRefreshCalendars;

  const SettingsView({
    super.key,
    required this.availableCalendars,
    required this.loadingCalendars,
    required this.onRefreshCalendars,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  Future<void> _useGps() async {
    final m = ScaffoldMessenger.of(context);
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      m.showSnackBar(SnackBar(
        content: Text(Tr.t(context, 'Location permission denied. Choose your city manually.', 'تم رفض إذن الموقع. يرجى اختيار المدينة يدوياً.')),
      ));
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
    m.showSnackBar(SnackBar(
      content: Text('${Tr.t(context, "Location set: ", "تم تحديد الموقع: ")}${Tr.city(context, st.city)}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: _useGps,
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

        // Android Setup Guide
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

        // iOS Setup Guide
        if (Platform.isIOS) ...[
          const SizedBox(height: 24),
          Text(Tr.t(context, 'iPhone Alarm & Notification setup', 'إعدادات المنبه والإشعارات للآيفون'), style: Theme.of(context).textTheme.titleSmall),
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
                      'To ensure prayer alarms ring reliably on your iPhone:\n\n'
                      '1. Tap "Notification Permission" below and allow notifications.\n'
                      '2. Make sure the physical mute/silent switch on your iPhone is OFF.\n'
                      '3. When an alarm rings on the lock screen, tap the banner to open and stop/snooze.',
                      'لضمان عمل منبهات الصلاة بدقة على جهاز الآيفون:\n\n'
                      '١. اضغط "إذن الإشعارات" بالأسفل وتأكد من السماح بالإشعارات والأصوات.\n'
                      '٢. تأكد من إيقاف وضع الصامت الفيزيائي (زر/مفتاح الصوت الجانبي) لسماع الرنين.\n'
                      '٣. عند رنين المنبه وشاشة الآيفون مقفلة، اضغط على شريط الإشعار لفتح التطبيق والإيقاف أو الغفوة.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.notifications_active, size: 18),
                        label: Text(Tr.t(context, 'Notification Permission', 'إذن الإشعارات')),
                        onPressed: () async {
                          await Permission.notification.request();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(Tr.t(context, 'Notification permission checked', 'تم التحقق من إذن الإشعارات'))),
                            );
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.settings, size: 18),
                        label: Text(Tr.t(context, 'iPhone Settings', 'إعدادات الآيفون')),
                        onPressed: () => openAppSettings(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        // Calendar Integration Section
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Tr.t(context, 'Calendar integration', 'ربط التقويم'), style: Theme.of(context).textTheme.titleSmall),
            IconButton(
              icon: widget.loadingCalendars
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
              tooltip: Tr.t(context, 'Refresh calendars', 'تحديث التقويمات'),
              onPressed: widget.loadingCalendars ? null : widget.onRefreshCalendars,
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
                if (widget.loadingCalendars && widget.availableCalendars == null)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (widget.availableCalendars == null || widget.availableCalendars!.isEmpty)
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
                              await widget.onRefreshCalendars();
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
                else ...[
                  DropdownButtonFormField<String>(
                    value: (widget.availableCalendars!.any((c) => c.id == st.defaultCalendarId))
                        ? st.defaultCalendarId
                        : widget.availableCalendars!.first.id,
                    decoration: InputDecoration(
                      labelText: Tr.t(context, 'Default calendar', 'التقويم الافتراضي'),
                      prefixIcon: const Icon(Icons.calendar_month),
                    ),
                    items: [
                      for (final cal in widget.availableCalendars!)
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}
