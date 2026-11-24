class Settings {
  String country = 'Egypt';
  String city = 'Alexandria';
  String method = 'egyptian';
  double lat = 31.2;
  double lng = 29.92;
  String timeFormat = 'system'; // 'system', '12h', '24h'
  String language = 'system';   // 'system', 'en', 'ar'
  String? defaultCalendarId;    // device calendar ID for "Add to Calendar"
  int calendarHorizonDays = 30; // Precalculated days for calendar events (14, 30, 60, 90, 180, 365)

  Map<String, dynamic> toJson() => {
    'country': country,
    'city': city,
    'method': method,
    'lat': lat,
    'lng': lng,
    'timeFormat': timeFormat,
    'language': language,
    'defaultCalendarId': defaultCalendarId,
    'calendarHorizonDays': calendarHorizonDays,
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
    defaultCalendarId = j['defaultCalendarId'];
    calendarHorizonDays = (j['calendarHorizonDays'] as num?)?.toInt() ?? 30;
  }
}

