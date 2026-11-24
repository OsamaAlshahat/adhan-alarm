import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import 'ar.dart';
import 'en.dart';

/// Localization helper for English and Arabic with automatic fallback
class Tr {
  static bool isAr(BuildContext? context) {
    if (context != null) {
      try {
        return Localizations.localeOf(context).languageCode == 'ar';
      } catch (_) {}
    }
    if (st.language == 'ar') return true;
    if (st.language == 'en') return false;
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ar';
  }

  static String t(BuildContext? context, String en, [String? ar]) {
    if (isAr(context)) {
      return ar ?? arStrings[en] ?? en;
    }
    return enStrings[en] ?? en;
  }

  static String prayer(BuildContext? context, String p) {
    if (isAr(context)) {
      return arPrayers[p] ?? p;
    }
    return enPrayers[p] ?? p;
  }

  static String method(BuildContext? context, String m) {
    if (isAr(context)) {
      return arMethods[m] ?? m;
    }
    return enMethods[m] ?? m;
  }

  static String country(BuildContext? context, String c) {
    if (isAr(context)) {
      return arCountries[c] ?? c;
    }
    return c;
  }

  static String city(BuildContext? context, String ct) {
    if (isAr(context)) {
      return arCities[ct] ?? ct;
    }
    return ct;
  }
}
