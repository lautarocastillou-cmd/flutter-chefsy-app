import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE11D48),
        surface: Color(0xFF1E293B),
      ),
      fontFamily: 'Roboto',
    );
  }
}
