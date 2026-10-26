import 'package:flutter/material.dart';

/// Token desain Smart POS Waroeng MeJeng Kampoeng (Prompt.md §3.1).
const brandPrimary = Color(0xFF930031);
const brandDark = Color(0xFF660023);
const brandSoft = Color(0xFFFBEAF0);
const canvasColor = Color(0xFFFCF8FA);
const surfaceColor = Color(0xFFFFFFFF);
const textPrimary = Color(0xFF21161C);
const textSecondary = Color(0xFF6E6268);
const borderColor = Color(0xFFE9DCE2);
const successColor = Color(0xFF187449);
const warningColor = Color(0xFFB96D14);
const errorColor = Color(0xFFB42318);

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandPrimary,
    brightness: Brightness.light,
  ).copyWith(
    primary: brandPrimary,
    onPrimary: Colors.white,
    secondary: brandDark,
    surface: surfaceColor,
    onSurface: textPrimary,
    error: errorColor,
    outline: borderColor,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvasColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceColor,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: borderColor),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(color: borderColor, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
    ),
  );
}
