import '../models/intensity_zone.dart';

/// Główny parser notatek treningowych
/// Buduje uproszczone AST z linii tekstu (regex-based line parser)
class SwimParser {
  final List<String> knownAthletes;
  final List<String> groupMembers;

  SwimParser({
    required this.knownAthletes,
    required this.groupMembers,
  });

  // --- Wyrażenia regularne ---
  static final _multiplierRe = RegExp(r'(\d+)[xX]', caseSensitive: false);
  static final _distanceRe = RegExp(r'(\d+)\s*m\b', caseSensitive: false);
  static final _numberRe = RegExp(r'(\d+)');
  static final _mmolRe = RegExp(r'(\d+[.,]\d+)\s*mmol', caseSensitive: false);
  static final _mmolRangeRe = RegExp(
    r'(\d+[.,]?\d*)-(\d+[.,]?\d*)\s*mmol',
    caseSensitive: false,
  );
  static final _pctRe = RegExp(r'(\d+)%');
  static final _sprintInDistRe = RegExp(
    r'(\d+)\s*m?\s*spr',
    caseSensitive: false,
  );
  static final _parenContentRe = RegExp(r'\(([^)]*)\)');
  static final _fractionalRe = RegExp(
    r'w\s+każd\w+\s+(\d+)[- ]?c\w*\s+[Ww]?\s*(\d+)\s*(spr|luz)',
    caseSensitive: false,
  );

  /// Szum – style pływackie (zawsze ignorowane)
  static final _strokeNoiseRe = RegExp(
    r'\b(k|st|zm|d|gr|mot|kl|grb|delf|klas|grzbiet|dowolny|motylek)\b',
    caseSensitive: false,
  );

  /// Szum – przerwy: p30, p30/20/15, w30, r30, itp.
  static final _restNoiseRe = RegExp(
    r'\b[pwrPWR]\d+(?:[/\d]*)\b',
  );

  // --- Mapowanie słów kluczowych stref ---
  static const Map<String, IntensityZone> _zoneMap = {
    'rozpł': IntensityZone.rec,
    'rozp': IntensityZone.rec,
    'luz': IntensityZone.rec,
    'ćw.t': IntensityZone.rec,
    'tlenowo': IntensityZone.en1,
    'tlen': IntensityZone.en1,
    'aktywny wypoczynek': IntensityZone.en1,
    'mocno': IntensityZone.en1,
    'progres': IntensityZone.en1,
    'progresja': IntensityZone.en1,
    'regres': IntensityZone.en1,
    'regresja': IntensityZone.en1,
    'progowo': IntensityZone.en2,
    'vo2 max': IntensityZone.en3,
    'vo2max': IntensityZone.en3,
    'spr': IntensityZone.sp3,
    '(o-a)': IntensityZone.sp3,
  };

  /// Parsuje cały tekst sesji
  ParsedSession parseSession(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final blocks = <ParsedBlock>[];

    List<String> currentAthletes = _expandGroup(groupMembers);
    bool isGroup = true;
    List<ParsedTask> currentTasks = [];
    int taskIndex = 0;

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;

      final headerResult = _tryParseHeader(line);
      if (headerResult != null) {
        if (currentTasks.isNotEmpty) {
          blocks.add(ParsedBlock(
            athletes: currentAthletes,
            isGroup: isGroup,
            tasks: List.from(currentTasks),
          ));
        }
        currentAthletes = headerResult.athletes;
        isGroup = headerResult.isGroup;
        currentTasks = [];
        taskIndex = 0;
        continue;
      }

      final task = _parseLine(line, taskIndex, currentAthletes);
      currentTasks.add(task);
      taskIndex++;
    }

    if (currentTasks.isNotEmpty) {
      blocks.add(ParsedBlock(
        athletes: currentAthletes,
        isGroup: isGroup,
        tasks: currentTasks,
      ));
    }

    return ParsedSession(blocks: blocks);
  }

  List<String> _expandGroup(List<String> members) =>
      members.isEmpty ? ['Grupa'] : members;

  _HeaderResult? _tryParseHeader(String line) {
    final trimmed = line.trim().replaceAll(':', '').trim();
    for (final name in knownAthletes) {
      if (trimmed.toLowerCase() == name.toLowerCase()) {
        return _HeaderResult(athletes: [name], isGroup: false);
      }
    }
    if (trimmed.toLowerCase() == 'grupa') {
      return _HeaderResult(athletes: _expandGroup(groupMembers), isGroup: true);
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // GŁÓWNA METODA PARSOWANIA LINII
  // ─────────────────────────────────────────────────────────────

  ParsedTask _parseLine(String line, int index, List<String> defaultAthletes) {
    final text = line.trim();

    // Wyodrębnij modyfikatory personalne (przed strippingiem)
    final personalMods = _extractPersonalMods(text);

    // Oczyść linię z szumu (styl + przerwy)
    final cleaned = _stripNoise(text);
    final cleanedLower = cleaned.toLowerCase();

    // --- Sprawdź czy to compound block: Nx(expr) ---
    final compound = _tryParseCompoundBlock(cleaned, index, defaultAthletes, personalMods);
    if (compound != null) return compound;

    // --- Sprawdź top-level mixed zones (bez nawiasów): "4x100 progowo + 4x50 tlenowo" ---
    final topLevel = _tryParseTopLevelMixed(cleaned, index, defaultAthletes, personalMods);
    if (topLevel != null) return topLevel;

    // --- Standardowe parsowanie z nawiasem (stare typy zadań) ---
    final parenMatches = _parenContentRe.allMatches(cleaned).toList();
    String mainText = _parenContentRe.hasMatch(cleaned)
        ? cleaned.replaceAll(_parenContentRe, ' ').trim()
        : cleaned;
    final parenContents = parenMatches.map((m) => m.group(1)!).toList();

    int multiplier = 1;
    double repDist = 0;

    final multMatch = _multiplierRe.firstMatch(mainText);
    if (multMatch != null) {
      multiplier = int.tryParse(multMatch.group(1)!) ?? 1;
      mainText = mainText.replaceFirst(multMatch.group(0)!, '').trim();
    }

    final distMatch = _distanceRe.firstMatch(mainText) ?? _numberRe.firstMatch(mainText);
    if (distMatch != null) {
      repDist = double.tryParse(distMatch.group(1)!) ?? 0;
    }

    final totalDist = multiplier * repDist;
    IntensityZone? baseZone = _detectZone(mainText);
    if (baseZone == null) {
      for (final paren in parenContents) {
        baseZone = _detectZone(paren);
        if (baseZone != null) break;
      }
    }

    if (parenContents.isNotEmpty) {
      final firstParen = parenContents.first.toLowerCase();

      // Sprint w dystansie "16x50 (20m spr)"
      final sprintMatch = _sprintInDistRe.firstMatch(firstParen);
      if (sprintMatch != null && repDist > 0) {
        final sprintDist = double.tryParse(sprintMatch.group(1)!) ?? 0;
        if (sprintDist < repDist) {
          return ParsedTask(
            sourceText: text,
            index: index,
            defaultAthletes: defaultAthletes,
            personalMods: personalMods,
            type: TaskType.sprintInDistance,
            data: {
              'repetitions': multiplier,
              'repDist': repDist,
              'sprintDist': sprintDist,
            },
          );
        }
      }

      // Wtrącenia frakcyjne "w każdej 100-ce W 25 spr"
      final fracMatch = _fractionalRe.firstMatch(firstParen);
      if (fracMatch != null && repDist > 0) {
        final sectionSize = double.tryParse(fracMatch.group(1)!) ?? 0;
        final insertDist = double.tryParse(fracMatch.group(2)!) ?? 0;
        final insertType = fracMatch.group(3)!.toLowerCase();
        return ParsedTask(
          sourceText: text,
          index: index,
          defaultAthletes: defaultAthletes,
          personalMods: personalMods,
          type: TaskType.fractionalInsert,
          data: {
            'repetitions': multiplier,
            'repDist': repDist,
            'sectionSize': sectionSize,
            'insertDist': insertDist,
            'insertZone': insertType == 'spr' ? IntensityZone.sp3 : IntensityZone.rec,
            'baseZone': baseZone ?? IntensityZone.en1,
          },
        );
      }

      // Cykle "6 cykli spr / 12 luz"
      if (firstParen.contains('cykl') || firstParen.contains('/')) {
        final groups = _parseCycleGroups(firstParen);
        if (groups.isNotEmpty && repDist > 0) {
          return ParsedTask(
            sourceText: text,
            index: index,
            defaultAthletes: defaultAthletes,
            personalMods: personalMods,
            type: TaskType.cyclicSplit,
            data: {
              'repetitions': multiplier,
              'repDist': repDist,
              'cycleGroups': groups,
            },
          );
        }
      }

      // Zakres mmol "2-3 mmol"
      final mmolRangeMatch = _mmolRangeRe.firstMatch(firstParen);
      if (mmolRangeMatch != null && repDist > 0) {
        final low = double.tryParse(mmolRangeMatch.group(1)!.replaceAll(',', '.')) ?? 0;
        final high = double.tryParse(mmolRangeMatch.group(2)!.replaceAll(',', '.')) ?? 0;
        return ParsedTask(
          sourceText: text,
          index: index,
          defaultAthletes: defaultAthletes,
          personalMods: personalMods,
          type: TaskType.mmolRange,
          data: {
            'repetitions': multiplier,
            'repDist': repDist,
            'mmolLow': low,
            'mmolHigh': high,
          },
        );
      }

      // Selekcja powtórzeń "4-7-9-10zm mocno"
      final selReps = _parseRepetitionSelection(firstParen);
      if (selReps != null && repDist > 0) {
        return ParsedTask(
          sourceText: text,
          index: index,
          defaultAthletes: defaultAthletes,
          personalMods: personalMods,
          type: TaskType.repetitionSelection,
          data: {
            'totalReps': multiplier,
            'repDist': repDist,
            'selectedReps': selReps['reps'],
            'selectedZone': selReps['zone'] ?? baseZone ?? IntensityZone.en1,
            'baseZone': baseZone ?? IntensityZone.en1,
          },
        );
      }

      // Podział stref w nawiasie "200tlen+50 95%"
      final splits = _parseZoneSplits(firstParen);
      if (splits != null && splits.isNotEmpty && repDist > 0) {
        return ParsedTask(
          sourceText: text,
          index: index,
          defaultAthletes: defaultAthletes,
          personalMods: personalMods,
          type: TaskType.splitDistance,
          data: {
            'repetitions': multiplier,
            'splits': splits,
          },
        );
      }
    }

    // Modyfikatory P-L, ćw.t-R
    if (cleanedLower.contains('p-l')) {
      return ParsedTask(
        sourceText: text,
        index: index,
        defaultAthletes: defaultAthletes,
        personalMods: personalMods,
        type: TaskType.splitZone,
        data: {
          'totalMeters': totalDist,
          'zone1': IntensityZone.en1,
          'fraction1': 0.5,
          'zone2': IntensityZone.rec,
          'fraction2': 0.5,
        },
      );
    }
    if (cleanedLower.contains('ćw.t-r')) {
      return ParsedTask(
        sourceText: text,
        index: index,
        defaultAthletes: defaultAthletes,
        personalMods: personalMods,
        type: TaskType.splitZone,
        data: {
          'totalMeters': totalDist,
          'zone1': IntensityZone.rec,
          'fraction1': 0.5,
          'zone2': IntensityZone.en1,
          'fraction2': 0.5,
        },
      );
    }

    // Zadanie standardowe
    return ParsedTask(
      sourceText: text,
      index: index,
      defaultAthletes: defaultAthletes,
      personalMods: personalMods,
      type: TaskType.standard,
      data: {
        'totalMeters': totalDist,
        'zone': baseZone,
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STRIP NOISE
  // ─────────────────────────────────────────────────────────────

  /// Usuwa szum pływacki i przerwy z tekstu, zostawiając liczby, strefy, mnożniki
  String _stripNoise(String text) {
    // Usuń szum stylów pływackich
    var result = text.replaceAll(_strokeNoiseRe, ' ');
    // Usuń przerwy (p30, w30/20/15, r30)
    result = result.replaceAll(_restNoiseRe, ' ');
    // Kompaktuj spacje
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // COMPOUND BLOCK: Nx(Mx<dist> + Mx<dist> + ...)
  // ─────────────────────────────────────────────────────────────

  /// Wykrywa i parsuje compound block: Nx(...)
  /// Compound = zewnętrzny mnożnik + nawias z sumą elementów Mx<dist>
  ParsedTask? _tryParseCompoundBlock(
    String text,
    int index,
    List<String> defaultAthletes,
    List<PersonalModData> personalMods,
  ) {
    // Wzorzec: cyfry+x na początku (po oczyszczeniu), po czym nawias
    final outerRe = RegExp(r'^(\d+)[xX]\s*\(([^)]+)\)', caseSensitive: false);
    final m = outerRe.firstMatch(text.trim());
    if (m == null) return null;

    final outerMult = int.tryParse(m.group(1)!) ?? 1;
    final innerExpr = m.group(2)!;

    // Parsuj elementy wewnątrz nawiasu jako sumę Mx<dist> lub <dist>
    // Element: opcjonalny "Nx" potem cyfry (dystans), reszta to szum
    final innerBlocks = _parseInnerBlocks(innerExpr);
    if (innerBlocks.isEmpty) return null;

    // Oblicz sumę wewnętrzną
    final innerTotal = innerBlocks.fold(0.0, (s, b) => s + (b['meters'] as double));
    if (innerTotal <= 0) return null;

    // Strefa – szukaj po nawiasie
    final afterParen = text.substring(m.end).trim();
    final zone = _detectZone(afterParen) ?? _detectZone(text) ?? IntensityZone.en1;

    // Sprawdź czy jest strefa per-element wewnątrz (compound mixed)
    // Jeśli każdy element ma strefę → compound mixed
    final hasMixedZones = innerBlocks.any((b) => b['zone'] != null);

    return ParsedTask(
      sourceText: text,
      index: index,
      defaultAthletes: defaultAthletes,
      personalMods: personalMods,
      type: TaskType.compoundBlock,
      data: {
        'outerMult': outerMult,
        'innerTotal': innerTotal,
        'innerBlocks': innerBlocks, // List<Map<String,dynamic>>
        'zone': zone,
        'hasMixedZones': hasMixedZones,
      },
    );
  }

  /// Parsuje elementy wewnątrz nawiasu: "1x300 + 2x150 + 3x100 + 6x25"
  /// Rozdziela po +
  List<Map<String, dynamic>> _parseInnerBlocks(String expr) {
    final blocks = <Map<String, dynamic>>[];
    final parts = expr.split('+');

    for (final rawPart in parts) {
      // Oczyść szum stylów w każdym elemencie
      final part = rawPart.replaceAll(_strokeNoiseRe, ' ').trim();
      if (part.isEmpty) continue;

      int mult = 1;
      double dist = 0;

      // Szukaj Nx na początku
      final multM = RegExp(r'^(\d+)[xX]', caseSensitive: false).firstMatch(part);
      if (multM != null) {
        mult = int.tryParse(multM.group(1)!) ?? 1;
        final rest = part.substring(multM.end).trim();
        final distM = _distanceRe.firstMatch(rest) ?? _numberRe.firstMatch(rest);
        if (distM != null) dist = double.tryParse(distM.group(1)!) ?? 0;
      } else {
        // Samo cyfry
        final distM = _distanceRe.firstMatch(part) ?? _numberRe.firstMatch(part);
        if (distM != null) dist = double.tryParse(distM.group(1)!) ?? 0;
      }

      if (dist <= 0) continue;

      // Strefa w elemencie (opcjonalna)
      final zone = _detectZone(part);

      blocks.add({
        'mult': mult,
        'meters': mult * dist,
        'zone': zone, // null = brak per-element strefy
      });
    }

    return blocks;
  }

  // ─────────────────────────────────────────────────────────────
  // TOP-LEVEL MIXED ZONES: "4x100 EN2 + 4x50 EN1"
  // ─────────────────────────────────────────────────────────────

  /// Wykrywa top-level mixed zone (+ na poziomie głównym, poza nawiasem)
  ParsedTask? _tryParseTopLevelMixed(
    String text,
    int index,
    List<String> defaultAthletes,
    List<PersonalModData> personalMods,
  ) {
    // Tylko jeśli nie ma nawiasów i jest top-level "+"
    if (text.contains('(')) return null;
    if (!text.contains('+')) return null;

    final parts = text.split('+');
    if (parts.length < 2) return null;

    final segments = <Map<String, dynamic>>[];

    for (final rawPart in parts) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;

      int mult = 1;
      double dist = 0;

      final multM = _multiplierRe.firstMatch(part);
      if (multM != null) {
        mult = int.tryParse(multM.group(1)!) ?? 1;
        final rest = part.substring(multM.end).trim();
        final distM = _distanceRe.firstMatch(rest) ?? _numberRe.firstMatch(rest);
        if (distM != null) dist = double.tryParse(distM.group(1)!) ?? 0;
      } else {
        final distM = _distanceRe.firstMatch(part) ?? _numberRe.firstMatch(part);
        if (distM != null) dist = double.tryParse(distM.group(1)!) ?? 0;
      }

      if (dist <= 0) continue;

      final zone = _detectZone(part) ?? IntensityZone.en1;
      final meters = mult * dist;

      segments.add({'meters': meters, 'zone': zone});
    }

    if (segments.length < 2) return null;

    return ParsedTask(
      sourceText: text,
      index: index,
      defaultAthletes: defaultAthletes,
      personalMods: personalMods,
      type: TaskType.splitDistance,
      data: {
        'repetitions': 1,
        'splits': segments,
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // POMOCNICZE
  // ─────────────────────────────────────────────────────────────

  IntensityZone? _detectZone(String text) {
    final lower = text.toLowerCase();

    if (_pctRe.firstMatch(text) != null) {
      final pct = int.tryParse(_pctRe.firstMatch(text)!.group(1)!) ?? 0;
      if (pct >= 95) return IntensityZone.sp2;
    }

    final mmolRange = _mmolRangeRe.firstMatch(lower);
    if (mmolRange != null) {
      final low = double.tryParse(mmolRange.group(1)!.replaceAll(',', '.')) ?? 0;
      final high = double.tryParse(mmolRange.group(2)!.replaceAll(',', '.')) ?? 0;
      return IntensityZone.fromMmol((low + high) / 2);
    }

    final mmol = _mmolRe.firstMatch(lower);
    if (mmol != null) {
      final val = double.tryParse(mmol.group(1)!.replaceAll(',', '.')) ?? 0;
      return IntensityZone.fromMmol(val);
    }

    final sortedKeys = _zoneMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final kw in sortedKeys) {
      if (lower.contains(kw)) return _zoneMap[kw]!;
    }

    return null;
  }

  List<PersonalModData> _extractPersonalMods(String text) {
    final mods = <PersonalModData>[];
    final lower = text.toLowerCase();

    for (final name in knownAthletes) {
      final nameLower = name.toLowerCase();
      int idx = lower.indexOf(nameLower);
      if (idx < 0) continue;

      final afterName = idx + name.length;
      final remaining = text.substring(afterName).trim();

      // Mnożnik po nazwie: "Wika 1x"
      final multAfter = RegExp(r'^(\d+)[xX]').firstMatch(remaining);
      if (multAfter != null) {
        mods.add(PersonalModData(
          name: name,
          multiplier: int.tryParse(multAfter.group(1)!) ?? 1,
        ));
        continue;
      }

      // Override dystansu: "Wika 1000 tlenowo"
      final distAfter = RegExp(r'^(\d+)').firstMatch(remaining);
      if (distAfter != null) {
        final overrideM = double.tryParse(distAfter.group(1)!) ?? 0;
        final zoneAfter = _detectZone(remaining);
        mods.add(PersonalModData(
          name: name,
          multiplier: 1,
          overrideMeters: overrideM,
          overrideZone: zoneAfter,
        ));
        continue;
      }

      mods.add(PersonalModData(name: name, multiplier: 1));
    }

    return mods;
  }

  List<Map<String, dynamic>> _parseCycleGroups(String text) {
    final groups = <Map<String, dynamic>>[];
    final parts = text.split(RegExp(r'[/,]'));
    for (final part in parts) {
      final lower = part.trim().toLowerCase();
      final numMatch = _numberRe.firstMatch(lower);
      if (numMatch == null) continue;
      final count = int.tryParse(numMatch.group(1)!) ?? 0;
      final zone = _detectZone(lower) ?? IntensityZone.en1;
      groups.add({'count': count, 'zone': zone});
    }
    return groups;
  }

  List<Map<String, dynamic>>? _parseZoneSplits(String text) {
    final splitRe = RegExp(r'(\d+)\s*([a-zA-ZąćęłńóśźżĄĆĘŁŃÓŚŹŻ.]+)', caseSensitive: false);
    final matches = splitRe.allMatches(text).toList();
    if (matches.isEmpty) return null;

    final splits = <Map<String, dynamic>>[];
    for (final m in matches) {
      final dist = double.tryParse(m.group(1)!) ?? 0;
      final zoneStr = m.group(2)!;
      final zone = _detectZone(zoneStr) ?? _detectZone(text) ?? IntensityZone.en1;
      splits.add({'meters': dist, 'zone': zone});
    }

    final pctMatch = _pctRe.firstMatch(text);
    if (pctMatch != null) {
      final pct = int.tryParse(pctMatch.group(1)!) ?? 0;
      if (pct >= 95 && splits.isNotEmpty) {
        splits.last['zone'] = IntensityZone.sp2;
      }
    }

    return splits.isNotEmpty ? splits : null;
  }

  Map<String, dynamic>? _parseRepetitionSelection(String text) {
    final selRe = RegExp(r'^([\d](?:[-–][\d]+)*)\s*[a-zA-ZąćęłńóśźżĄĆĘŁŃÓŚŹŻ]');
    final match = selRe.firstMatch(text.trim());
    if (match == null) return null;

    final numsStr = match.group(1)!;
    final reps = numsStr
        .split(RegExp(r'[-–]'))
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .where((n) => n > 0)
        .toList();

    if (reps.length < 2) return null;

    final zone = _detectZone(text);
    return {'reps': reps, 'zone': zone};
  }
}

// --- Pomocnicze modele dla parsera ---

class ParsedSession {
  final List<ParsedBlock> blocks;
  ParsedSession({required this.blocks});
}

class ParsedBlock {
  final List<String> athletes;
  final bool isGroup;
  final List<ParsedTask> tasks;
  ParsedBlock({required this.athletes, required this.isGroup, required this.tasks});
}

enum TaskType {
  standard,
  sprintInDistance,
  fractionalInsert,
  cyclicSplit,
  mmolRange,
  repetitionSelection,
  splitDistance,
  splitZone,
  compoundBlock, // NEW: Nx(Mx<dist>+Mx<dist>+...)
}

class ParsedTask {
  final String sourceText;
  final int index;
  final List<String> defaultAthletes;
  final List<PersonalModData> personalMods;
  final TaskType type;
  final Map<String, dynamic> data;

  ParsedTask({
    required this.sourceText,
    required this.index,
    required this.defaultAthletes,
    required this.personalMods,
    required this.type,
    required this.data,
  });
}

class PersonalModData {
  final String name;
  final int multiplier;
  final double? overrideMeters;
  final IntensityZone? overrideZone;

  PersonalModData({
    required this.name,
    required this.multiplier,
    this.overrideMeters,
    this.overrideZone,
  });
}

class _HeaderResult {
  final List<String> athletes;
  final bool isGroup;
  _HeaderResult({required this.athletes, required this.isGroup});
}
