import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../parser/models/parse_result.dart';
import '../parser/models/intensity_zone.dart';

// ─────────────────────────────────────────────────────────────
// MODELE
// ─────────────────────────────────────────────────────────────

/// Pomiar laktatowy z automatyczną strefą
class LactateEntry {
  final String id;
  final String sessionId;
  final String athleteName;
  final double value; // mmol/L
  final DateTime recordedAt;

  LactateEntry({
    String? id,
    required this.sessionId,
    required this.athleteName,
    required this.value,
    required this.recordedAt,
  }) : id = id ?? const Uuid().v4();

  /// Strefa laktatowa – INNE zakresy niż strefa dystansu
  IntensityZone get zone => LactateZone.fromValue(value);
}

/// Mapowanie mmol/L → strefa (laktaty) – spójne z parserem
/// Rec 0-2.0 | EN1 2.1-3.5 | EN2 3.6-6.0 | EN3 6.1-8.0 | SP1 >8.0 | SP2/SP3 = max/sprint
class LactateZone {
  static IntensityZone fromValue(double v) {
    if (v <= 2.0) return IntensityZone.rec;
    if (v <= 3.5) return IntensityZone.en1;
    if (v <= 6.0) return IntensityZone.en2;
    if (v <= 8.0) return IntensityZone.en3;
    return IntensityZone.sp1; // >8.0 – max
  }

  static String rangeLabel(IntensityZone z) {
    switch (z) {
      case IntensityZone.rec:  return '0.0 – 2.0';
      case IntensityZone.en1:  return '2.1 – 3.5';
      case IntensityZone.en2:  return '3.6 – 6.0';
      case IntensityZone.en3:  return '6.1 – 8.0';
      case IntensityZone.sp1:  return '> 8.0';
      case IntensityZone.sp2:  return 'max';
      case IntensityZone.sp3:  return 'sprint';
    }
  }

  /// Wszystkie strefy wyświetlane w tabeli laktatów
  static const displayZones = [
    IntensityZone.rec,
    IntensityZone.en1,
    IntensityZone.en2,
    IntensityZone.en3,
    IntensityZone.sp1,
    IntensityZone.sp2,
    IntensityZone.sp3,
  ];
}

/// Model sesji treningowej
class TrainingSession {
  final String id;
  final DateTime date;
  final String rawText;
  final List<ZoneEntry> entries;
  final String note;
  final String name; // etykieta/nazwa sesji, np. "Obóz Wisła"
  final List<LactateEntry> lactates;

  TrainingSession({
    String? id,
    required this.date,
    required this.rawText,
    required this.entries,
    this.note = '',
    this.name = '',
    List<LactateEntry>? lactates,
  })  : id = id ?? const Uuid().v4(),
        lactates = lactates ?? [];

  double get totalMeters => entries.fold(0.0, (s, e) => s + e.meters);
  List<String> get athletes => entries.map((e) => e.athleteName).toSet().toList();

  /// Metry w danej strefie dla tej sesji
  double metersInZone(IntensityZone z) =>
      entries.where((e) => e.zone == z).fold(0.0, (s, e) => s + e.meters);
}

/// Skumulowane statystyki narastające
class CumulativeStats {
  final double totalMeters;
  final Map<IntensityZone, double> metersByZone;
  final List<LactateEntry> allLactates;

  CumulativeStats({
    required this.totalMeters,
    required this.metersByZone,
    required this.allLactates,
  });

  double percentForZone(IntensityZone z) {
    if (totalMeters <= 0) return 0;
    return (metersByZone[z] ?? 0) / totalMeters;
  }

  /// Wszystkie laktaty w danej strefie
  List<LactateEntry> lactatesInZone(IntensityZone z) =>
      allLactates.where((l) => l.zone == z).toList();

  double avgLactateInZone(IntensityZone z) {
    final list = lactatesInZone(z);
    if (list.isEmpty) return 0;
    return list.map((l) => l.value).reduce((a, b) => a + b) / list.length;
  }
}

// ─────────────────────────────────────────────────────────────
// REPOZYTORIUM
// ─────────────────────────────────────────────────────────────

class SessionRepository extends ChangeNotifier {
  static const _sessionsTable = 'sessions';
  static const _entriesTable = 'session_entries';
  static const _lactatesTable = 'lactate_entries';

  Database? _db;
  List<TrainingSession> _sessions = [];

  List<TrainingSession> get sessions => List.unmodifiable(_sessions);

  /// Sesje posortowane rosnąco wg daty (dla narastających obliczeń)
  List<TrainingSession> get sessionsByDate {
    final sorted = [..._sessions];
    sorted.sort((a, b) => a.date.compareTo(b.date));
    return sorted;
  }

  /// Wszyscy zawodnicy ze wszystkich sesji (posortowane alfabetycznie)
  List<String> get allAthletes {
    final names = <String>{};
    for (final s in _sessions) {
      for (final e in s.entries) {
        names.add(e.athleteName);
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  /// Sesje zawierające wpisy dla danego zawodnika
  List<TrainingSession> sessionsForAthlete(String athlete) {
    return _sessions
        .where((s) => s.entries.any((e) => e.athleteName == athlete))
        .toList();
  }

  /// Statystyki miesięczne dla konkretnego zawodnika
  CumulativeStats monthlyStatsForAthlete(int year, int month, String athlete) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final inMonth = sessionsByDate
        .where((s) => !s.date.isBefore(start) && s.date.isBefore(end))
        .toList();

    double total = 0;
    final byZone = <IntensityZone, double>{};
    final allLactates = <LactateEntry>[];

    for (final session in inMonth) {
      final athleteEntries = session.entries.where((e) => e.athleteName == athlete);
      for (final entry in athleteEntries) {
        total += entry.meters;
        byZone[entry.zone] = (byZone[entry.zone] ?? 0) + entry.meters;
      }
      allLactates.addAll(session.lactates.where((l) => l.athleteName == athlete));
    }

    return CumulativeStats(
      totalMeters: total,
      metersByZone: byZone,
      allLactates: allLactates,
    );
  }

  // ── Inicjalizacja ────────────────────────────────────────────

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'swim_sessions.db'),
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _loadSessions();
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_sessionsTable (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        rawText TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_entriesTable (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        athleteName TEXT NOT NULL,
        zone TEXT NOT NULL,
        meters REAL NOT NULL,
        sourceText TEXT NOT NULL,
        FOREIGN KEY(sessionId) REFERENCES $_sessionsTable(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_lactatesTable (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL,
        athleteName TEXT NOT NULL,
        value REAL NOT NULL,
        recordedAt TEXT NOT NULL,
        FOREIGN KEY(sessionId) REFERENCES $_sessionsTable(id)
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Dodaj kolumnę name jeśli nie istnieje
      try {
        await db.execute(
            "ALTER TABLE $_sessionsTable ADD COLUMN name TEXT NOT NULL DEFAULT ''");
      } catch (_) {} // ignoruj jeśli już istnieje

      // Stwórz tabelę laktatów
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_lactatesTable (
          id TEXT PRIMARY KEY,
          sessionId TEXT NOT NULL,
          athleteName TEXT NOT NULL,
          value REAL NOT NULL,
          recordedAt TEXT NOT NULL,
          FOREIGN KEY(sessionId) REFERENCES $_sessionsTable(id)
        )
      ''');
    }
  }

  // ── Wczytywanie ──────────────────────────────────────────────

  Future<void> _loadSessions() async {
    final sessionMaps = await _db!.query(
      _sessionsTable,
      orderBy: 'date DESC',
    );

    final sessions = <TrainingSession>[];
    for (final sMap in sessionMaps) {
      final id = sMap['id'] as String;

      final entryMaps = await _db!.query(
        _entriesTable,
        where: 'sessionId = ?',
        whereArgs: [id],
      );

      final lactateMaps = await _db!.query(
        _lactatesTable,
        where: 'sessionId = ?',
        whereArgs: [id],
        orderBy: 'recordedAt ASC',
      );

      final entries = entryMaps
          .map((e) => ZoneEntry(
                athleteName: e['athleteName'] as String,
                zone: IntensityZone.values.firstWhere(
                  (z) => z.name == e['zone'],
                  orElse: () => IntensityZone.en1,
                ),
                meters: (e['meters'] as num).toDouble(),
                sourceText: e['sourceText'] as String,
              ))
          .toList();

      final lactates = lactateMaps
          .map((l) => LactateEntry(
                id: l['id'] as String,
                sessionId: id,
                athleteName: l['athleteName'] as String,
                value: (l['value'] as num).toDouble(),
                recordedAt: DateTime.parse(l['recordedAt'] as String),
              ))
          .toList();

      sessions.add(TrainingSession(
        id: id,
        date: DateTime.parse(sMap['date'] as String),
        rawText: sMap['rawText'] as String,
        note: sMap['note'] as String? ?? '',
        name: sMap['name'] as String? ?? '',
        entries: entries,
        lactates: lactates,
      ));
    }

    _sessions = sessions;
    notifyListeners();
  }

  // ── Zapis sesji ──────────────────────────────────────────────

  Future<void> saveSession(TrainingSession session) async {
    await _db!.insert(
      _sessionsTable,
      {
        'id': session.id,
        'date': session.date.toIso8601String(),
        'rawText': session.rawText,
        'note': session.note,
        'name': session.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db!.delete(_entriesTable,
        where: 'sessionId = ?', whereArgs: [session.id]);

    for (final entry in session.entries) {
      await _db!.insert(_entriesTable, {
        'id': const Uuid().v4(),
        'sessionId': session.id,
        'athleteName': entry.athleteName,
        'zone': entry.zone.name,
        'meters': entry.meters,
        'sourceText': entry.sourceText,
      });
    }

    await _loadSessions();
  }

  Future<void> updateSessionName(String sessionId, String name) async {
    await _db!.update(
      _sessionsTable,
      {'name': name},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await _loadSessions();
  }

  Future<void> deleteSession(String id) async {
    await _db!.delete(_sessionsTable, where: 'id = ?', whereArgs: [id]);
    await _db!.delete(_entriesTable,
        where: 'sessionId = ?', whereArgs: [id]);
    await _db!.delete(_lactatesTable,
        where: 'sessionId = ?', whereArgs: [id]);
    await _loadSessions();
  }

  // ── Laktaty ──────────────────────────────────────────────────

  Future<LactateEntry> addLactate(LactateEntry entry) async {
    await _db!.insert(_lactatesTable, {
      'id': entry.id,
      'sessionId': entry.sessionId,
      'athleteName': entry.athleteName,
      'value': entry.value,
      'recordedAt': entry.recordedAt.toIso8601String(),
    });
    await _loadSessions();
    return entry;
  }

  Future<void> deleteLactate(String lactateId) async {
    await _db!
        .delete(_lactatesTable, where: 'id = ?', whereArgs: [lactateId]);
    await _loadSessions();
  }

  // ── Statystyki skumulowane ───────────────────────────────────

  /// Oblicza narastające statystyki dla wszystkich sesji
  /// do podanej daty włącznie (posortowane rosnąco).
  CumulativeStats cumulativeStatsUpTo(DateTime date) {
    final sorted = sessionsByDate
        .where((s) => !s.date.isAfter(date))
        .toList();

    double total = 0;
    final byZone = <IntensityZone, double>{};
    final allLactates = <LactateEntry>[];

    for (final session in sorted) {
      total += session.totalMeters;
      for (final z in IntensityZone.values) {
        byZone[z] = (byZone[z] ?? 0) + session.metersInZone(z);
      }
      allLactates.addAll(session.lactates);
    }

    return CumulativeStats(
      totalMeters: total,
      metersByZone: byZone,
      allLactates: allLactates,
    );
  }

  /// Narastające statystyki dla konkretnego zawodnika do podanej daty
  CumulativeStats cumulativeStatsForAthlete(DateTime date, String athlete) {
    final sorted = sessionsByDate
        .where((s) => !s.date.isAfter(date))
        .toList();

    double total = 0;
    final byZone = <IntensityZone, double>{};
    final allLactates = <LactateEntry>[];

    for (final session in sorted) {
      final athleteEntries = session.entries.where((e) => e.athleteName == athlete);
      for (final entry in athleteEntries) {
        total += entry.meters;
        byZone[entry.zone] = (byZone[entry.zone] ?? 0) + entry.meters;
      }
      allLactates.addAll(session.lactates.where((l) => l.athleteName == athlete));
    }

    return CumulativeStats(
      totalMeters: total,
      metersByZone: byZone,
      allLactates: allLactates,
    );
  }

  /// Statystyki dla bieżącego miesiąca
  CumulativeStats monthlyStats(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final inMonth = sessionsByDate
        .where((s) => !s.date.isBefore(start) && s.date.isBefore(end))
        .toList();

    double total = 0;
    final byZone = <IntensityZone, double>{};
    final allLactates = <LactateEntry>[];

    for (final session in inMonth) {
      total += session.totalMeters;
      for (final z in IntensityZone.values) {
        byZone[z] = (byZone[z] ?? 0) + session.metersInZone(z);
      }
      allLactates.addAll(session.lactates);
    }

    return CumulativeStats(
      totalMeters: total,
      metersByZone: byZone,
      allLactates: allLactates,
    );
  }
}
