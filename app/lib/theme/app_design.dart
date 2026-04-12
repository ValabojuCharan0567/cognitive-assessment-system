import 'package:flutter/material.dart';

class AppDesign {
  static const Color bg = Color(0xFF0F172A);
  static const Color surface = Color(0xFF111827);
  static const Color surfaceAlt = Color(0xFF1E293B);
  static const Color primary = Color(0xFF14B8A6);
  static const Color onSurfaceMuted = Color(0xFFCBD5E1);

  static const double radiusS = 10;
  static const double radiusM = 14;
  static const double radiusL = 18;

  static const EdgeInsets pagePadding = EdgeInsets.all(18);

  static ThemeData theme() {
    final base = ThemeData.dark(useMaterial3: true);
    const scheme = ColorScheme.dark(
      primary: primary,
      secondary: Color(0xFF22D3EE),
      surface: surface,
      onSurface: Colors.white,
      onPrimary: Colors.black,
    );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      cardColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
          color: Colors.white,
        ),
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        bodyLarge: const TextStyle(fontSize: 15, height: 1.45),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(fontSize: 12.5, color: onSurfaceMuted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: primary.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
          borderRadius: BorderRadius.circular(radiusM),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF233244),
          disabledForegroundColor: Colors.white54,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: Colors.white,
          backgroundColor: surfaceAlt.withValues(alpha: 0.55),
          side: BorderSide(color: primary.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF67E8F9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusS),
          ),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: onSurfaceMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: primary, width: 1.3),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.12),
        thickness: 1,
      ),
    );
  }
}
