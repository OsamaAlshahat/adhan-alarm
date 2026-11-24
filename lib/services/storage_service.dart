import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_model.dart';
import '../models/settings_model.dart';

late SharedPreferences prefs;
Settings st = Settings();
List<Al> alarms = [];
final ValueNotifier<Locale?> appLocaleNotifier = ValueNotifier<Locale?>(null);

Locale? getLocaleFromSetting(String lang) {
  if (lang == 'ar') return const Locale('ar');
  if (lang == 'en') return const Locale('en');
  return null; // System default: follow phone language
}

Future<void> initStorage() async {
  prefs = await SharedPreferences.getInstance();
  final s = prefs.getString('st');
  if (s != null) st = Settings.from(jsonDecode(s));
  final l = prefs.getString('al');
  if (l != null) alarms = (jsonDecode(l) as List).map((e) => Al.from(e)).toList();
  appLocaleNotifier.value = getLocaleFromSetting(st.language);
}

void save() {
  prefs.setString('st', jsonEncode(st.toJson()));
  prefs.setString('al', jsonEncode(alarms.map((a) => a.toJson()).toList()));
}
