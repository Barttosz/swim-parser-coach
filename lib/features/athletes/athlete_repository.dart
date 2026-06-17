import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models/athlete.dart';

/// Repozytorium zawodników – SQLite
class AthleteRepository extends ChangeNotifier {
  static const _tableName = 'athletes';
  Database? _db;

  List<Athlete> _athletes = [];

  List<Athlete> get athletes => List.unmodifiable(_athletes);
  List<String> get groupMembers =>
      _athletes.where((a) => a.isInGroup).map((a) => a.name).toList();
  List<String> get allNames => _athletes.map((a) => a.name).toList();
  Athlete? findById(String id) => _athletes.where((a) => a.id == id).firstOrNull;

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'swim_parser.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            isInGroup INTEGER NOT NULL DEFAULT 1
          )
        ''');
        // Przykładowi zawodnicy
        await db.insert(_tableName, Athlete(name: 'Wika').toMap());
        await db.insert(_tableName, Athlete(name: 'Darul').toMap());
      },
    );
    await _loadAthletes();
  }

  Future<void> _loadAthletes() async {
    final maps = await _db!.query(_tableName, orderBy: 'name ASC');
    _athletes = maps.map((m) => Athlete.fromMap(m)).toList();
    notifyListeners();
  }

  Future<void> addAthlete(String name) async {
    if (name.trim().isEmpty) return;
    final athlete = Athlete(name: name.trim());
    await _db!.insert(_tableName, athlete.toMap());
    await _loadAthletes();
  }

  Future<void> removeAthlete(String id) async {
    await _db!.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    await _loadAthletes();
  }

  Future<void> updateAthlete(Athlete athlete) async {
    await _db!.update(
      _tableName,
      athlete.toMap(),
      where: 'id = ?',
      whereArgs: [athlete.id],
    );
    await _loadAthletes();
  }

  Future<void> toggleGroupMembership(String id) async {
    final athlete = _athletes.firstWhere((a) => a.id == id);
    await updateAthlete(athlete.copyWith(isInGroup: !athlete.isInGroup));
  }
}
