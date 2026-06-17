import 'package:flutter/material.dart';

/// Kolory z DESIGN.md – SwimStats Pro
class AppColors {
  AppColors._();

  // --- Kolory podstawowe ---
  static const Color primary = Color(0xFF003E7A);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF0055A4);
  static const Color onPrimaryContainer = Color(0xFFAFCCFF);
  static const Color inversePrimary = Color(0xFFA8C8FF);

  static const Color secondary = Color(0xFF006A65);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFF76F3EA);
  static const Color onSecondaryContainer = Color(0xFF006F69);

  static const Color tertiary = Color(0xFF354400);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF4A5D00);
  static const Color onTertiaryContainer = Color(0xFFB0DB00);

  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // --- Powierzchnie ---
  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceDim = Color(0xFFD8DADC);
  static const Color surfaceBright = Color(0xFFF7F9FB);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF2F4F6);
  static const Color surfaceContainer = Color(0xFFECEEF0);
  static const Color surfaceContainerHigh = Color(0xFFE6E8EA);
  static const Color surfaceContainerHighest = Color(0xFFE0E3E5);
  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF424751);
  static const Color inverseSurface = Color(0xFF2D3133);
  static const Color inverseOnSurface = Color(0xFFEFF1F3);
  static const Color surfaceVariant = Color(0xFFE0E3E5);
  static const Color surfaceTint = Color(0xFF175EAD);

  static const Color background = Color(0xFFF7F9FB);
  static const Color onBackground = Color(0xFF191C1E);
  static const Color outline = Color(0xFF727783);
  static const Color outlineVariant = Color(0xFFC2C6D3);

  // --- Akcenty specjalne ---
  /// Chlorine Teal – interaktywne stany, highlight parsera
  static const Color chlorineTeal = Color(0xFF006A65);
  static const Color chlorineTealLight = Color(0xFF76F3EA);
  /// Neon Volt – szczyty intensywności
  static const Color neonVolt = Color(0xFFB0DB00);

  // --- Semantyczne kolory stref intensywności ---
  static const Color zoneRecBg = Color(0xFFE8F5E9);
  static const Color zoneRecFg = Color(0xFF1B5E20);
  static const Color zoneRecBorder = Color(0xFFA5D6A7);

  static const Color zoneEn1Bg = Color(0xFFE3F2FD);
  static const Color zoneEn1Fg = Color(0xFF0D47A1);
  static const Color zoneEn1Border = Color(0xFF90CAF9);

  static const Color zoneEn2Bg = Color(0xFFFFF9C4);
  static const Color zoneEn2Fg = Color(0xFFF57F17);
  static const Color zoneEn2Border = Color(0xFFFFF176);

  static const Color zoneEn3Bg = Color(0xFFFFE0B2);
  static const Color zoneEn3Fg = Color(0xFFE65100);
  static const Color zoneEn3Border = Color(0xFFFFCC80);

  static const Color zoneSp1Bg = Color(0xFFFFCCBC);
  static const Color zoneSp1Fg = Color(0xFFBF360C);
  static const Color zoneSp1Border = Color(0xFFFF8A65);

  static const Color zoneSp2Bg = Color(0xFF8D1B9E);
  static const Color zoneSp2Fg = Color(0xFFFFFFFF);
  static const Color zoneSp2Border = Color(0xFFCE93D8);

  static const Color zoneSp3Bg = Color(0xFFB71C1C);
  static const Color zoneSp3Fg = Color(0xFFFFFFFF);
  static const Color zoneSp3Border = Color(0xFFEF9A9A);

  // --- Helper – kolor tła strefy ---
  static Color zoneBg(String zone) {
    switch (zone.toLowerCase()) {
      case 'rec': return zoneRecBg;
      case 'en1': return zoneEn1Bg;
      case 'en2': return zoneEn2Bg;
      case 'en3': return zoneEn3Bg;
      case 'sp1': return zoneSp1Bg;
      case 'sp2': return zoneSp2Bg;
      case 'sp3': return zoneSp3Bg;
      default: return surfaceContainerLow;
    }
  }

  static Color zoneFg(String zone) {
    switch (zone.toLowerCase()) {
      case 'rec': return zoneRecFg;
      case 'en1': return zoneEn1Fg;
      case 'en2': return zoneEn2Fg;
      case 'en3': return zoneEn3Fg;
      case 'sp1': return zoneSp1Fg;
      case 'sp2': return zoneSp2Fg;
      case 'sp3': return zoneSp3Fg;
      default: return onSurface;
    }
  }

  static Color zoneBorder(String zone) {
    switch (zone.toLowerCase()) {
      case 'rec': return zoneRecBorder;
      case 'en1': return zoneEn1Border;
      case 'en2': return zoneEn2Border;
      case 'en3': return zoneEn3Border;
      case 'sp1': return zoneSp1Border;
      case 'sp2': return zoneSp2Border;
      case 'sp3': return zoneSp3Border;
      default: return outlineVariant;
    }
  }
}
