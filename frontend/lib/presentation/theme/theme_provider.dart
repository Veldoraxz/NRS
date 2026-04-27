// lib/presentation/theme/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado global de tema (claro/oscuro). Por defecto, claro.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.light;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void setMode(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(() => ThemeModeNotifier());

class AppTheme {
  // Colores base (existentes)
  static const Color primaryBlue     = Color(0xFF0F4C81);
  static const Color secondaryBlue   = Color(0xFF1E88E5);
  static const Color backgroundLight = Color(0xFFF5F7FA);
  static const Color cardLight       = Colors.white;
  static const Color textDark        = Color(0xFF2C3E50);

  // Aliases usados en widgets
  static const Color cardColor   = Color(0xFFECF4FF);
  static const Color accentColor = primaryBlue;
  static const Color textColor   = textDark;

  // Colores de estado
  static const Color statusAvailable = Color(0xFF27AE60);
  static const Color statusInUse     = Color(0xFFE67E22);
  static const Color statusMaint     = Color(0xFFE74C3C);
  static const Color statusOff       = Color(0xFF95A5A6);

  // Warning (cuenta en aire)
  static const Color warningColor = Color(0xFFF39C12);

  static ThemeData get deepSeaTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: backgroundLight,
      primaryColor: primaryBlue,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: secondaryBlue,
        surface: cardLight,
        onPrimary: Colors.white,
        onSurface: textDark,
      ),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: textDark),
        bodyMedium: TextStyle(color: textDark),
        titleLarge: TextStyle(color: textDark, fontWeight: FontWeight.bold),
      ),
      cardTheme: CardThemeData(
        color: cardLight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryBlue,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: textDark),
      ),
    );
  }

  /// Variante oscura usando los mismos acentos.
  static ThemeData get nightTheme {
    const darkBg     = Color(0xFF0E1421);
    const darkCard   = Color(0xFF182333);
    const darkText   = Color(0xFFE8EDF5);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: secondaryBlue,
      colorScheme: const ColorScheme.dark(
        primary: secondaryBlue,
        secondary: Color(0xFF00F2FF),
        surface: darkCard,
        onPrimary: Colors.white,
        onSurface: darkText,
      ),
      textTheme: const TextTheme(
        bodyLarge:  TextStyle(color: darkText),
        bodyMedium: TextStyle(color: darkText),
        titleLarge: TextStyle(color: darkText, fontWeight: FontWeight.bold),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        elevation: 1,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1A2C),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF00F2FF), width: 2),
        ),
        labelStyle: const TextStyle(color: darkText),
      ),
    );
  }
}
