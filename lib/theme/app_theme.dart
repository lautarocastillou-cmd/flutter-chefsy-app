import 'package:flutter/material.dart';

class AppTheme {
  static const Color chefsyGreen = Color(0xFF014B44);
  static const Color chefsyDark = Color(0xFF002723);
  static const Color chefsyCard = Color(0xFF023631);
  static const Color chefsyLight = Color(0xFF026D62);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF014B44),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF014B44),
        surface: Color(0xFF023631),
        onPrimary: Colors.white,
        onSurface: Colors.white,
      ),
      fontFamily: 'Roboto',
    );
  }
}
