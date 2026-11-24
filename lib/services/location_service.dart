import 'package:adhan/adhan.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_constants.dart';
import '../models/alarm_model.dart';
import 'storage_service.dart';

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

Future<Position?> getCurrentGpsPosition() async {
  try {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.whileInUse || p == LocationPermission.always) {
      return await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 8));
    }
    return null;
  } catch (_) {
    return null;
  }
}

