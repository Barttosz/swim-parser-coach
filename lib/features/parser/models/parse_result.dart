import 'intensity_zone.dart';

/// Wynik parsowania – jeden wpis (zawodnik + strefa + metry)
class ZoneEntry {
  final String athleteName;
  final IntensityZone zone;
  double meters;
  final String sourceText; // oryginalna linia źródłowa

  ZoneEntry({
    required this.athleteName,
    required this.zone,
    required this.meters,
    required this.sourceText,
  });

  ZoneEntry copyWith({
    String? athleteName,
    IntensityZone? zone,
    double? meters,
    String? sourceText,
  }) {
    return ZoneEntry(
      athleteName: athleteName ?? this.athleteName,
      zone: zone ?? this.zone,
      meters: meters ?? this.meters,
      sourceText: sourceText ?? this.sourceText,
    );
  }

  @override
  String toString() => 'ZoneEntry($athleteName, ${zone.label}, ${meters}m)';
}

/// Wynik parsowania całej sesji
class ParseResult {
  final List<ZoneEntry> entries;
  final List<String> warnings;

  ParseResult({required this.entries, this.warnings = const []});

  /// Łączny dystans dla danego zawodnika
  double totalMetersFor(String athlete) {
    return entries
        .where((e) => e.athleteName == athlete)
        .fold(0.0, (sum, e) => sum + e.meters);
  }

  /// Łączny dystans dla danej strefy
  double totalMetersInZone(IntensityZone zone) {
    return entries
        .where((e) => e.zone == zone)
        .fold(0.0, (sum, e) => sum + e.meters);
  }

  double get totalMeters => entries.fold(0.0, (sum, e) => sum + e.meters);

  List<String> get athletes =>
      entries.map((e) => e.athleteName).toSet().toList();
}
