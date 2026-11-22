// core/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // CycloneX brand colours
  static const Color primary    = Color(0xFF00D4FF);  // cyan
  static const Color secondary  = Color(0xFF7B2FBE);  // deep purple
  static const Color danger     = Color(0xFFFF3B3B);  // red SOS
  static const Color warning    = Color(0xFFFFAA00);  // amber
  static const Color surface    = Color(0xFF0F1624);  // dark surface
  static const Color card       = Color(0xFF1A2235);  // card bg
  static const Color cardLight  = Color(0xFF232E45);  // slightly lighter card
  static const Color textPrimary   = Color(0xFFEAF0FF);
  static const Color textSecondary = Color(0xFF8A97B0);
  static const Color onlineGreen   = Color(0xFF00E676);

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: surface,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      error: danger,
      surface: surface,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
      bodyLarge:  const TextStyle(color: textPrimary),
      bodyMedium: const TextStyle(color: textSecondary),
      titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: textPrimary),
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: primary.withOpacity(0.15),
      iconTheme: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const IconThemeData(color: primary, size: 24);
        }
        return const IconThemeData(color: textSecondary, size: 22);
      }),
      labelTextStyle: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: textSecondary, fontSize: 11);
      }),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: textSecondary),
    ),
  );
}
