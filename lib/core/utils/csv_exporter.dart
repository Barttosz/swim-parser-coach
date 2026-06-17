import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:swim_parser/features/parser/models/parse_result.dart';
import 'package:swim_parser/features/parser/models/intensity_zone.dart';

/// Eksport wyników do CSV
class CsvExporter {
  /// Eksportuje ParseResult do pliku CSV i udostępnia przez share sheet
  static Future<void> exportAndShare(
    ParseResult result, {
    required DateTime sessionDate,
  }) async {
    final rows = <List<dynamic>>[
      // Nagłówek
      ['Zawodnik', 'Strefa', 'Metry'],
    ];

    // Pogrupuj wpisy per zawodnik, posortuj
    final athletes = result.athletes..sort();
    for (final athlete in athletes) {
      for (final zone in IntensityZone.values) {
        final meters = result.entries
            .where((e) => e.athleteName == athlete && e.zone == zone)
            .fold(0.0, (s, e) => s + e.meters);
        if (meters > 0) {
          rows.add([athlete, zone.label, meters.toStringAsFixed(0)]);
        }
      }
      // Suma dla zawodnika
      rows.add([athlete, 'SUMA', result.totalMetersFor(athlete).toStringAsFixed(0)]);
      rows.add(['', '', '']); // pusty wiersz separator
    }

    // Łączna suma
    rows.add(['ŁĄCZNIE', '', result.totalMeters.toStringAsFixed(0)]);

    final csv = const CsvEncoder(
      fieldDelimiter: ';',
      lineDelimiter: '\n',
    ).convert(rows);

    // Zapisz do pliku tymczasowego
    final dir = await getTemporaryDirectory();
    final dateStr =
        '${sessionDate.year}-${sessionDate.month.toString().padLeft(2, '0')}-${sessionDate.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/trening_$dateStr.csv');
    await file.writeAsString(csv, encoding: utf8);

    // Udostępnij
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Trening – $dateStr',
        subject: 'Wyniki treningu pływackiego',
      ),
    );
  }
}
