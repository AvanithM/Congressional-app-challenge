import 'package:flutter/material.dart';

const coral = Color.fromARGB(255, 14, 1, 123);
const lavender = Color(0xFF9B8AFB);
const turquoise = Color(0xFF42D6C5);
const sunshine = Color(0xFFFFD166);
const ink = Color(0xFF292746);
const softBackground = Color(0xFFFFF8F5);

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: softBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: lavender,
      primary: lavender,
      secondary: turquoise,
      tertiary: coral,
      surface: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: softBackground,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}