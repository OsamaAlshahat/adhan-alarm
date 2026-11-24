import 'package:flutter/material.dart';

class AppTheme {
  static const primaryColor = Color(0xFF0C5A58);
  static const primaryDarkColor = Color(0xFF147A78);
  static const accentGold = Color(0xFFE5B54F);

  static final ThemeData lightTheme = ThemeData(
    colorSchemeSeed: primaryColor,
    scaffoldBackgroundColor: const Color(0xFFF4F7F6),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    colorSchemeSeed: primaryDarkColor,
    scaffoldBackgroundColor: const Color(0xFF051719),
    brightness: Brightness.dark,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
  );
}
