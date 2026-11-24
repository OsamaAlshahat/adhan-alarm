import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../localization/tr.dart';

bool is24HourFormat(BuildContext? context) {
  if (st.timeFormat == '12h') return false;
  if (st.timeFormat == '24h') return true;
  if (context != null) {
    try {
      return MediaQuery.alwaysUse24HourFormatOf(context);
    } catch (_) {}
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
