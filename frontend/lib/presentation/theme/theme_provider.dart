import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0E1116);
  static const Color cardColor = Color(0xFF374A67);
  static const Color accentColor = Color(0xFF98B9F2);
  static const Color textColor = Color(0xFFD7DCEA);

  static ThemeData get deepSeaTheme {
    return ThemeData(
      scaffoldBackgroundColor: background,
      primaryColor: accentColor,
      colorScheme: const ColorScheme.dark(
        primary: accentColor,
        surface: cardColor,
        background: background,
        onPrimary: background,
        onSurface: textColor,
        onBackground: textColor,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textColor),
        bodyMedium: TextStyle(color: textColor),
        titleLarge: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        iconTheme: IconThemeData(color: accentColor),
        titleTextStyle: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
