import 'package:adhan/adhan.dart';
import 'package:flutter/services.dart';

const prayers = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];

const methods = {
  'egyptian': CalculationMethod.egyptian,
  'mwl': CalculationMethod.muslim_world_league,
  'makkah': CalculationMethod.umm_al_qura,
  'karachi': CalculationMethod.karachi,
  'isna': CalculationMethod.north_america,
};

// country -> [city, lat, lng] (built in, offline)
const cities = <String, List<List<Object>>>{
  'Egypt': [
    ['Alexandria', 31.2, 29.92],
    ['Cairo', 30.04, 31.24],
    ['Giza', 30.01, 31.21],
    ['Mansoura', 31.04, 31.38],
    ['Tanta', 30.79, 31.0],
    ['Port Said', 31.27, 32.3],
    ['Suez', 29.97, 32.55],
    ['Luxor', 25.69, 32.64],
    ['Aswan', 24.09, 32.9],
    ['Assiut', 27.18, 31.18],
  ],
  'Saudi Arabia': [
    ['Makkah', 21.42, 39.83],
    ['Madinah', 24.47, 39.61],
    ['Riyadh', 24.71, 46.68],
    ['Jeddah', 21.54, 39.17],
  ],
  'UAE': [
    ['Dubai', 25.2, 55.27],
    ['Abu Dhabi', 24.45, 54.38],
  ],
  'Jordan': [
    ['Amman', 31.95, 35.93],
  ],
  'Palestine': [
    ['Jerusalem', 31.77, 35.21],
  ],
  'Kuwait': [
    ['Kuwait City', 29.38, 47.99],
  ],
  'Qatar': [
    ['Doha', 25.29, 51.53],
  ],
  'Iraq': [
    ['Baghdad', 33.31, 44.37],
  ],
  'Morocco': [
    ['Casablanca', 33.57, -7.59],
  ],
  'Algeria': [
    ['Algiers', 36.75, 3.06],
  ],
  'Tunisia': [
    ['Tunis', 36.81, 10.18],
  ],
  'Turkey': [
    ['Istanbul', 41.01, 28.98],
  ],
  'Pakistan': [
    ['Karachi', 24.86, 67.01],
  ],
  'Indonesia': [
    ['Jakarta', -6.2, 106.85],
  ],
  'United Kingdom': [
    ['London', 51.51, -0.13],
  ],
  'United States': [
    ['New York', 40.71, -74.01],
  ],
};

const dailyRescheduleTaskKey = 'adhan_alarm_daily_reschedule';
const platformFullscreen = MethodChannel('com.adhan_alarm.app/fullscreen_settings');
