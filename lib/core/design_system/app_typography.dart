import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typografia z DESIGN.md – SwimStats Pro
class AppTypography {
  AppTypography._();

  // --- Inter (UI) ---
  static TextStyle get displayLg => GoogleFonts.inter(
    fontSize: 48,
    fontWeight: FontWeight.w800,
    height: 56 / 48,
    letterSpacing: -0.02 * 48,
  );

  static TextStyle get headlineMd => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
  );

  static TextStyle get headlineSm => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 28 / 20,
  );

  static TextStyle get headlineMdMobile => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 28 / 20,
  );

  static TextStyle get bodyLg => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
  );

  static TextStyle get bodySm => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
  );

  static TextStyle get labelCaps => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 16 / 12,
    letterSpacing: 0.05 * 12,
  );

  // --- JetBrains Mono (dane techniczne / parser) ---
  static TextStyle get dataMono => GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
  );

  static TextStyle get dataMonoLg => GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
  );
}
