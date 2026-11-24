/// English language strings, prayer names, methods, and day translations.

const weekDaysEn = [
  {'day': DateTime.monday, 'name': 'Monday', 'short': 'Mon'},
  {'day': DateTime.tuesday, 'name': 'Tuesday', 'short': 'Tue'},
  {'day': DateTime.wednesday, 'name': 'Wednesday', 'short': 'Wed'},
  {'day': DateTime.thursday, 'name': 'Thursday', 'short': 'Thu'},
  {'day': DateTime.friday, 'name': 'Friday', 'short': 'Fri'},
  {'day': DateTime.saturday, 'name': 'Saturday', 'short': 'Sat'},
  {'day': DateTime.sunday, 'name': 'Sunday', 'short': 'Sun'},
];

const enPrayers = <String, String>{
  'fajr': 'Fajr',
  'sunrise': 'Sunrise',
  'dhuhr': 'Dhuhr',
  'asr': 'Asr',
  'maghrib': 'Maghrib',
  'isha': 'Isha',
};

const enMethods = <String, String>{
  'egyptian': 'Egyptian General Authority',
  'mwl': 'Muslim World League',
  'makkah': 'Umm al-Qura (Makkah)',
  'karachi': 'Karachi',
  'isna': 'ISNA (North America)',
};

const enStrings = <String, String>{
  // General & Navigation
  'Mee3ad': 'Mee3ad',
  'Awan': 'Mee3ad',
  'Alarms': 'Alarms',
  'Settings': 'Settings',
  'Alarm': 'Alarm',
  'Save': 'Save',
  'Cancel': 'Cancel',
  'Delete': 'Delete',
  'Stop': 'Stop',
  'Snooze 5 min': 'Snooze 5 min',
  'All': 'All',
  'Calendar': 'Calendar',
  'Normal': 'Normal',
  'in calendar': 'In Calendar',

  // Empty states
  'No alarms yet. Tap “New alarm”.': 'No alarms yet. Tap “New alarm”.',
  'No alarms with calendar sync.': 'No alarms with calendar sync.',
  'No normal alarms without calendar.': 'No normal alarms without calendar.',

  // Alarm Edit Sheet
  'New alarm': 'New alarm',
  'Edit alarm': 'Edit alarm',
  'Normal time': 'Normal time',
  'Prayer time': 'Prayer time',
  'Exact time': 'Exact time',
  'Before': 'Before',
  'After': 'After',
  'Hours': 'Hours',
  'Minutes': 'Minutes',
  'Repeat': 'Repeat',
  'Only once': 'Only once',
  'Every day': 'Every day',
  'Specific days': 'Specific days',
  'Days': 'Days',
  'Sound & Alerts': 'Sound & Alerts',
  'Sound': 'Sound',
  'Vibration': 'Vibration',
  'Notification': 'Notification',
  'Choose ring sound': 'Choose ring sound',
  'Default ring': 'Default ring',
  'Label': 'Label',
  'Alarm label': 'Alarm label or notes',
  'Add to Calendar': 'Add to Calendar',
  'Use app default': 'Use app default',
  'Events generation horizon': 'Events generation horizon',
  'Event duration': 'Event duration',
  'days': 'days',
  'day': 'day',

  // Settings Screen
  'Language': 'Language',
  'Follow system': 'Follow system',
  'Arabic': 'Arabic',
  'English': 'English',
  'Time format': 'Time format',
  'System format': 'System format',
  '12-hour (AM/PM)': '12-hour (AM/PM)',
  '24-hour': '24-hour',
  'Location': 'Location',
  'Country': 'Country',
  'City': 'City',
  'Use GPS Location': 'Use GPS Location',
  'Getting GPS location...': 'Getting GPS location...',
  'Prayer calculation method': 'Prayer calculation method',
  'Calendar Integration': 'Calendar Integration',
  'Default calendar': 'Default calendar',
  'Default calendar horizon': 'Default calendar sync horizon',
  'No writable calendar found': 'No writable calendar found',
  'Device calendar permission is required': 'Device calendar permission is required',
  'Syncing all alarms to calendar...': 'Syncing all alarms to calendar...',
  'Calendar sync completed': 'Calendar sync completed',
  'Sync Now': 'Sync Now',

  // Permissions & Setup Guides
  'Alarm ring & full screen setup': 'Alarm ring & full screen setup',
  'iPhone Alarm & Notification setup': 'iPhone Alarm & Notification setup',
  'Notification Permission': 'Notification Permission',
  'Notification permission checked': 'Notification permission checked',
  'iPhone Settings': 'iPhone Settings',
  'Permission Settings': 'Permission Settings',
  'Battery Optimization': 'Battery Optimization',
  'Exact Alarm Permission': 'Exact Alarm Permission',
  'Full Screen Permission': 'Full Screen Permission',
  'Display Over Other Apps': 'Display Over Other Apps',

  // Android Instructions
  'android_guidance': 'To ensure alarm rings on time and displays full screen even when device is locked:',
  'android_exact_alarm': '• Exact Alarms: Required to ring at the exact minute without delay.',
  'android_battery': '• Ignore Battery Optimization: Prevents Android from killing background alarms.',
  'android_fullscreen': '• Full Screen & Lock Screen: Opens the alarm view immediately.',

  // iOS Instructions
  'ios_guidance': 'To ensure prayer alarms ring reliably on your iPhone:\n\n'
      '1. Tap "Notification Permission" below and allow notifications.\n'
      '2. Make sure the physical mute/silent switch on your iPhone is OFF.\n'
      '3. When an alarm rings on the lock screen, tap the banner to open and stop/snooze.',
};

