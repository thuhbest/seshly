import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SeshlyPalette {
  static const Color background = Color(0xFF08111F);
  static const Color surface = Color(0xFF101C2E);
  static const Color surfaceRaised = Color(0xFF16253C);
  static const Color edge = Color(0xFF263B59);
  static const Color aqua = Color(0xFF6FF2D4);
  static const Color cyan = Color(0xFF41C7FF);
  static const Color gold = Color(0xFFF4C96C);
  static const Color rose = Color(0xFFFF8A72);
  static const Color textPrimary = Color(0xFFF7F4EC);
  static const Color textMuted = Color(0xFFAAB6CB);
}

class SeshlyTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: SeshlyPalette.aqua,
      secondary: SeshlyPalette.gold,
      tertiary: SeshlyPalette.rose,
      surface: SeshlyPalette.surface,
      surfaceContainerHighest: SeshlyPalette.surfaceRaised,
      onPrimary: SeshlyPalette.background,
      onSecondary: SeshlyPalette.background,
      onSurface: SeshlyPalette.textPrimary,
      outline: SeshlyPalette.edge,
      error: Color(0xFFFF6F7D),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: SeshlyPalette.background,
      splashFactory: InkRipple.splashFactory,
      dividerColor: Colors.white.withValues(alpha: 0.08),
    );

    final textTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme)
        .copyWith(
          displayLarge: GoogleFonts.playfairDisplay(
            color: SeshlyPalette.textPrimary,
            fontSize: 42,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.4,
          ),
          displayMedium: GoogleFonts.playfairDisplay(
            color: SeshlyPalette.textPrimary,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
          ),
          headlineMedium: GoogleFonts.playfairDisplay(
            color: SeshlyPalette.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          titleLarge: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          bodyMedium: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.textMuted,
            fontSize: 14,
            height: 1.5,
          ),
          bodySmall: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.textMuted,
            fontSize: 12,
          ),
          labelLarge: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.background,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          labelMedium: GoogleFonts.spaceGrotesk(
            color: SeshlyPalette.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: SeshlyPalette.textPrimary),
      ),
      iconTheme: const IconThemeData(color: SeshlyPalette.textPrimary),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SeshlyPalette.surfaceRaised,
        contentTextStyle: GoogleFonts.spaceGrotesk(
          color: SeshlyPalette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SeshlyPalette.aqua,
          foregroundColor: SeshlyPalette.background,
          elevation: 0,
          textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SeshlyPalette.gold,
          foregroundColor: SeshlyPalette.background,
          textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        hintStyle: GoogleFonts.spaceGrotesk(
          color: SeshlyPalette.textMuted.withValues(alpha: 0.75),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: SeshlyPalette.aqua, width: 1.2),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SeshlyPalette.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
