/// Strefa intensywności treningu pływackiego
enum IntensityZone {
  rec,
  en1,
  en2,
  en3,
  sp1,
  sp2,
  sp3;

  String get label {
    switch (this) {
      case IntensityZone.rec: return 'Rec';
      case IntensityZone.en1: return 'EN1';
      case IntensityZone.en2: return 'EN2';
      case IntensityZone.en3: return 'EN3';
      case IntensityZone.sp1: return 'SP1';
      case IntensityZone.sp2: return 'SP2';
      case IntensityZone.sp3: return 'SP3';
    }
  }

  String get description {
    switch (this) {
      case IntensityZone.rec: return 'Regeneracja (0–2.0 mmol)';
      case IntensityZone.en1: return 'Tlenowo (2.1–3.5 mmol)';
      case IntensityZone.en2: return 'Progowo (3.6–6.0 mmol)';
      case IntensityZone.en3: return 'VO2 max (6.1–8.0 mmol)';
      case IntensityZone.sp1: return 'Szybkościowo 1 (>8.0 mmol)';
      case IntensityZone.sp2: return 'Szybkościowo 2 (max mmol / 95%)';
      case IntensityZone.sp3: return 'Sprint (maksymalny)';
    }
  }

  static IntensityZone? fromMmol(double mmol) {
    if (mmol <= 2.0) return IntensityZone.rec;
    if (mmol <= 3.5) return IntensityZone.en1;
    if (mmol <= 6.0) return IntensityZone.en2;
    if (mmol <= 8.0) return IntensityZone.en3;
    return IntensityZone.sp1;
  }

  static IntensityZone? fromMmolRange(double low, double high) {
    // Jeśli przedział obejmuje dokładnie jedną strefę – zwróć ją
    final lowZone = IntensityZone.fromMmol(low);
    final highZone = IntensityZone.fromMmol(high);
    if (lowZone == highZone) return lowZone;
    return null; // przedział zahacza o wiele stref → obsługiwane przez evaluator
  }

  static List<(IntensityZone, double)> splitByMmolRange(double low, double high, double totalMeters) {
    // Proporcjonalny podział dystansu między strefy z zakresu mmol
    final List<(IntensityZone, double)> result = [];
    // Granice stref
    final List<(double, double, IntensityZone)> zones = [
      (0.0, 2.0, IntensityZone.rec),
      (2.1, 3.5, IntensityZone.en1),
      (3.6, 6.0, IntensityZone.en2),
      (6.1, 8.0, IntensityZone.en3),
      (8.1, double.infinity, IntensityZone.sp1),
    ];
    final rangeSize = high - low;
    for (final (zLow, zHigh, zone) in zones) {
      final overlap = _overlap(low, high, zLow, zHigh);
      if (overlap > 0 && rangeSize > 0) {
        final fraction = overlap / rangeSize;
        result.add((zone, totalMeters * fraction));
      }
    }
    return result;
  }

  static double _overlap(double a1, double a2, double b1, double b2) {
    final start = a1 > b1 ? a1 : b1;
    final end = a2 < b2 ? a2 : b2;
    return end > start ? end - start : 0;
  }
}
