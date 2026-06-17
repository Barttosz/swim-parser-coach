import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────
// MODELE
// ─────────────────────────────────────────────────────────────

enum EventType {
  mainStart,      // Główny start (BPS)
  secondaryStart, // Start poboczny
  other,          // Inne wydarzenie
}

extension EventTypeExt on EventType {
  String get label {
    switch (this) {
      case EventType.mainStart:      return 'Główny start';
      case EventType.secondaryStart: return 'Start poboczny';
      case EventType.other:          return 'Inne';
    }
  }

  String get icon {
    switch (this) {
      case EventType.mainStart:      return '🏆';
      case EventType.secondaryStart: return '🏅';
      case EventType.other:          return '📌';
    }
  }

  bool get hasBps =>
      this == EventType.mainStart || this == EventType.secondaryStart;
}

class CalendarEvent {
  final String id;
  final DateTime date;
  final EventType type;
  final String name;
  final int? bpsWeeks; // null = bez BPS

  CalendarEvent({
    String? id,
    required this.date,
    required this.type,
    required this.name,
    this.bpsWeeks,
  }) : id = id ?? const Uuid().v4();

  /// Data początku BPS (jeśli zdefiniowany)
  DateTime? get bpsStartDate =>
      bpsWeeks != null ? date.subtract(Duration(days: bpsWeeks! * 7)) : null;

  /// Czy podana data jest w oknie BPS?
  bool isInBpsWindow(DateTime d) {
    final bps = bpsStartDate;
    if (bps == null) return false;
    return !d.isBefore(bps) && !d.isAfter(date);
  }

  /// Dni do eventu (ujemne = event minął)
  int daysUntil() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    return eventDay.difference(today).inDays;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'type': type.name,
        'name': name,
        'bpsWeeks': bpsWeeks,
      };

  static CalendarEvent fromMap(Map<String, dynamic> m) => CalendarEvent(
        id: m['id'] as String,
        date: DateTime.parse(m['date'] as String),
        type: EventType.values.firstWhere(
          (e) => e.name == m['type'],
          orElse: () => EventType.other,
        ),
        name: m['name'] as String,
        bpsWeeks: m['bpsWeeks'] as int?,
      );
}

// ─────────────────────────────────────────────────────────────
// REPOZYTORIUM
// ─────────────────────────────────────────────────────────────

class CalendarEventRepository extends ChangeNotifier {
  static const _table = 'calendar_events';

  Database? _db;
  List<CalendarEvent> _events = [];

  List<CalendarEvent> get events => List.unmodifiable(_events);

  /// Eventy nadchodzące (od dziś w górę), posortowane rosnąco
  List<CalendarEvent> get upcomingEvents {
    final today = DateTime.now();
    return _events
        .where((e) => !e.date.isBefore(DateTime(today.year, today.month, today.day)))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Eventy w danym miesiącu
  List<CalendarEvent> eventsInMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return _events
        .where((e) => !e.date.isBefore(start) && e.date.isBefore(end))
        .toList();
  }

  /// Eventy w danym tygodniu (Mon–Sun)
  List<CalendarEvent> eventsInWeek(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return _events
        .where((e) => !e.date.isBefore(weekStart) && e.date.isBefore(weekEnd))
        .toList();
  }

  /// Wszystkie aktywne BPS windows – posortowane wg daty startu
  List<CalendarEvent> get bpsEvents =>
      _events.where((e) => e.bpsWeeks != null).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  /// Sprawdź czy dana data jest w jakimkolwiek BPS window
  bool isInAnyBps(DateTime date) =>
      bpsEvents.any((e) => e.isInBpsWindow(date));

  /// Pobierz event BPS-start dla dnia (jeśli dokładnie ten dzień = bpsStartDate)
  CalendarEvent? bpsStartEventForDay(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return bpsEvents.firstWhereOrNull((e) {
      final bps = e.bpsStartDate;
      if (bps == null) return false;
      return DateTime(bps.year, bps.month, bps.day) == d;
    });
  }

  // ── Inicjalizacja ─────────────────────────────────────────

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'calendar_events.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_table (
            id       TEXT PRIMARY KEY,
            date     TEXT NOT NULL,
            type     TEXT NOT NULL,
            name     TEXT NOT NULL,
            bpsWeeks INTEGER
          )
        ''');
      },
    );
    await _load();
  }

  Future<void> _load() async {
    final maps = await _db!.query(_table, orderBy: 'date ASC');
    _events = maps.map(CalendarEvent.fromMap).toList();
    notifyListeners();
  }

  // ── CRUD ─────────────────────────────────────────────────

  Future<CalendarEvent> addEvent(CalendarEvent event) async {
    await _db!.insert(_table, event.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _load();
    return event;
  }

  Future<void> deleteEvent(String id) async {
    await _db!.delete(_table, where: 'id = ?', whereArgs: [id]);
    await _load();
  }

  Future<void> updateEvent(CalendarEvent event) async {
    await _db!.update(_table, event.toMap(),
        where: 'id = ?', whereArgs: [event.id]);
    await _load();
  }
}

// ─────────────────────────────────────────────────────────────
// HELPER
// ─────────────────────────────────────────────────────────────

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
