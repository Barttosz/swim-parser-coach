import '../models/intensity_zone.dart';
import '../models/parse_result.dart';
import '../ast/parser.dart';

/// Evaluator – oblicza metry per zawodnik per strefa
/// na podstawie sparsowanego AST (ParsedSession)
class SwimEvaluator {
  final List<String> groupMembers;

  SwimEvaluator({required this.groupMembers});

  /// Główna metoda – przetwarza ParsedSession → ParseResult
  ParseResult evaluate(ParsedSession session) {
    final entries = <ZoneEntry>[];
    final warnings = <String>[];

    for (final block in session.blocks) {
      bool prevWasHighIntensity = false; // Złota Zasada #3

      for (int i = 0; i < block.tasks.length; i++) {
        final task = block.tasks[i];
        final isFirst = i == 0;

        final taskEntries = _evaluateTask(
          task: task,
          athletes: block.athletes,
          isFirstTask: isFirst,
          prevWasHighIntensity: prevWasHighIntensity,
          warnings: warnings,
        );

        entries.addAll(taskEntries);

        // Zaktualizuj stan dla Złotej Zasady #3
        prevWasHighIntensity = _isHighIntensityTask(task);
      }
    }

    return ParseResult(entries: entries, warnings: warnings);
  }

  bool _isHighIntensityTask(ParsedTask task) {
    if (task.type == TaskType.standard) {
      final zone = task.data['zone'] as IntensityZone?;
      return zone == IntensityZone.en2 || zone == IntensityZone.en3;
    }
    if (task.type == TaskType.mmolRange) {
      final low = task.data['mmolLow'] as double? ?? 0;
      final high = task.data['mmolHigh'] as double? ?? 0;
      final mid = (low + high) / 2;
      final zone = IntensityZone.fromMmol(mid);
      return zone == IntensityZone.en2 || zone == IntensityZone.en3;
    }
    return false;
  }

  List<ZoneEntry> _evaluateTask({
    required ParsedTask task,
    required List<String> athletes,
    required bool isFirstTask,
    required bool prevWasHighIntensity,
    required List<String> warnings,
  }) {
    final entries = <ZoneEntry>[];

    // Ustal efektywnych zawodników i ich mnożniki
    final athleteMults = _resolveAthleteMults(task, athletes);

    for (final entry in athleteMults.entries) {
      final athleteName = entry.key;
      final mult = entry.value;

      // Override dystansu personalnego
      final personalMod = task.personalMods
          .where((m) => m.name == athleteName)
          .firstOrNull;

      if (personalMod?.overrideMeters != null) {
        // Zawodnik ma własny dystans w tej linii
        final zone = personalMod!.overrideZone ?? IntensityZone.en1;
        entries.add(ZoneEntry(
          athleteName: athleteName,
          zone: zone,
          meters: personalMod.overrideMeters!,
          sourceText: task.sourceText,
        ));
        continue;
      }

      // Oblicz wpisy dla zadania
      final taskEntries = _calcEntries(
        task: task,
        athleteName: athleteName,
        multiplierOverride: mult,
        isFirstTask: isFirstTask,
        prevWasHighIntensity: prevWasHighIntensity,
        warnings: warnings,
      );
      entries.addAll(taskEntries);
    }

    return entries;
  }

  /// Rozwiązuje mnożniki per zawodnik
  Map<String, double> _resolveAthleteMults(ParsedTask task, List<String> athletes) {
    final result = <String, double>{};

    // Dla compoundBlock: domyślny mnożnik to outerMult zadania
    final defaultMult = task.type == TaskType.compoundBlock
        ? (task.data['outerMult'] as int? ?? 1).toDouble()
        : 1.0;

    for (final athlete in athletes) {
      result[athlete] = defaultMult;
    }

    // Nadpisz przez modyfikatory personalne
    for (final mod in task.personalMods) {
      if (athletes.contains(mod.name)) {
        // Dla compoundBlock: personalMod.multiplier = TARGET outerMult (np. Wika 1x → 1)
        // Dla innych zadań: personalMod.multiplier = mnożnik względny × normalnego dystansu
        result[mod.name] = mod.multiplier.toDouble();
      }
    }

    return result;
  }

  /// Oblicza wpisy dla konkretnego zawodnika i zadania
  List<ZoneEntry> _calcEntries({
    required ParsedTask task,
    required String athleteName,
    required double multiplierOverride,
    required bool isFirstTask,
    required bool prevWasHighIntensity,
    required List<String> warnings,
  }) {
    // Złota Zasada #2: pierwsze zadanie → Rec
    if (isFirstTask) {
      final meters = _getSimpleMeters(task) * multiplierOverride;
      if (meters > 0) {
        return [
          ZoneEntry(
            athleteName: athleteName,
            zone: IntensityZone.rec,
            meters: meters,
            sourceText: task.sourceText,
          )
        ];
      }
    }

    switch (task.type) {
      case TaskType.standard:
        return _evalStandard(task, athleteName, multiplierOverride, prevWasHighIntensity);

      case TaskType.sprintInDistance:
        return _evalSprintInDistance(task, athleteName, multiplierOverride);

      case TaskType.fractionalInsert:
        return _evalFractionalInsert(task, athleteName, multiplierOverride);

      case TaskType.cyclicSplit:
        return _evalCyclicSplit(task, athleteName, multiplierOverride);

      case TaskType.mmolRange:
        return _evalMmolRange(task, athleteName, multiplierOverride);

      case TaskType.repetitionSelection:
        return _evalRepetitionSelection(task, athleteName, multiplierOverride);

      case TaskType.splitDistance:
        return _evalSplitDistance(task, athleteName, multiplierOverride);

      case TaskType.splitZone:
        return _evalSplitZone(task, athleteName, multiplierOverride);

      case TaskType.compoundBlock:
        return _evalCompoundBlock(task, athleteName, multiplierOverride);
    }
  }

  double _getSimpleMeters(ParsedTask task) {
    switch (task.type) {
      case TaskType.standard:
      case TaskType.splitZone:
        return (task.data['totalMeters'] as double? ?? 0);
      case TaskType.sprintInDistance:
        return (task.data['repetitions'] as int? ?? 0) *
            (task.data['repDist'] as double? ?? 0);
      case TaskType.fractionalInsert:
        return (task.data['repetitions'] as int? ?? 0) *
            (task.data['repDist'] as double? ?? 0);
      case TaskType.cyclicSplit:
        return (task.data['repetitions'] as int? ?? 0) *
            (task.data['repDist'] as double? ?? 0);
      case TaskType.mmolRange:
        return (task.data['repetitions'] as int? ?? 0) *
            (task.data['repDist'] as double? ?? 0);
      case TaskType.repetitionSelection:
        return (task.data['totalReps'] as int? ?? 0) *
            (task.data['repDist'] as double? ?? 0);
      case TaskType.splitDistance:
        final reps = task.data['repetitions'] as int? ?? 0;
        final splits = task.data['splits'] as List<Map<String, dynamic>>? ?? [];
        return reps * splits.fold(0.0, (s, m) => s + (m['meters'] as double? ?? 0));
      case TaskType.compoundBlock:
        final outerMult = task.data['outerMult'] as int? ?? 1;
        final innerTotal = task.data['innerTotal'] as double? ?? 0;
        return outerMult * innerTotal;
    }
  }

  // --- Standard ---
  List<ZoneEntry> _evalStandard(ParsedTask task, String athlete, double mult, bool prevHigh) {
    final total = (task.data['totalMeters'] as double? ?? 0) * mult;
    IntensityZone zone = task.data['zone'] as IntensityZone? ?? IntensityZone.en1;

    // Złota Zasada #3: po high-intensity → Rec
    if (prevHigh && task.data['zone'] == null) {
      zone = IntensityZone.rec;
    }

    if (total <= 0) return [];
    return [ZoneEntry(athleteName: athlete, zone: zone, meters: total, sourceText: task.sourceText)];
  }

  // --- Sprint w dystansie: 16x50 (20m spr) ---
  List<ZoneEntry> _evalSprintInDistance(ParsedTask task, String athlete, double mult) {
    final reps = (task.data['repetitions'] as int? ?? 0);
    final repDist = (task.data['repDist'] as double? ?? 0);
    final sprintDist = (task.data['sprintDist'] as double? ?? 0);

    final sprintMeters = reps * sprintDist * mult;
    final recMeters = reps * (repDist - sprintDist) * mult;

    return [
      if (sprintMeters > 0)
        ZoneEntry(athleteName: athlete, zone: IntensityZone.sp3, meters: sprintMeters, sourceText: task.sourceText),
      if (recMeters > 0)
        ZoneEntry(athleteName: athlete, zone: IntensityZone.rec, meters: recMeters, sourceText: task.sourceText),
    ];
  }

  // --- Wtrącenia frakcyjne: 5x400 (w każdej 100-ce W 25 spr) ---
  List<ZoneEntry> _evalFractionalInsert(ParsedTask task, String athlete, double mult) {
    final reps = (task.data['repetitions'] as int? ?? 0);
    final repDist = (task.data['repDist'] as double? ?? 0);
    final sectionSize = (task.data['sectionSize'] as double? ?? 0);
    final insertDist = (task.data['insertDist'] as double? ?? 0);
    final insertZone = task.data['insertZone'] as IntensityZone? ?? IntensityZone.sp3;
    final baseZone = task.data['baseZone'] as IntensityZone? ?? IntensityZone.en1;

    if (sectionSize <= 0) return [];

    final sectionsPerRep = (repDist / sectionSize).floor();
    final sprintPerRep = sectionsPerRep * insertDist;
    final basePerRep = repDist - sprintPerRep;

    return [
      if (reps * sprintPerRep * mult > 0)
        ZoneEntry(
          athleteName: athlete,
          zone: insertZone,
          meters: reps * sprintPerRep * mult,
          sourceText: task.sourceText,
        ),
      if (reps * basePerRep * mult > 0)
        ZoneEntry(
          athleteName: athlete,
          zone: baseZone,
          meters: reps * basePerRep * mult,
          sourceText: task.sourceText,
        ),
    ];
  }

  // --- Cykl: 6x200 (6 cykli spr / 12 luz) ---
  List<ZoneEntry> _evalCyclicSplit(ParsedTask task, String athlete, double mult) {
    final reps = (task.data['repetitions'] as int? ?? 0);
    final repDist = (task.data['repDist'] as double? ?? 0);
    final groups = task.data['cycleGroups'] as List<Map<String, dynamic>>? ?? [];

    if (groups.isEmpty) return [];

    final totalCycles = groups.fold(0, (s, g) => s + (g['count'] as int? ?? 0));
    if (totalCycles == 0) return [];

    final totalDist = reps * repDist * mult;
    final result = <ZoneEntry>[];

    for (final group in groups) {
      final count = group['count'] as int? ?? 0;
      final zone = group['zone'] as IntensityZone? ?? IntensityZone.en1;
      final fraction = count / totalCycles;
      final meters = totalDist * fraction;
      if (meters > 0) {
        result.add(ZoneEntry(
          athleteName: athlete,
          zone: zone,
          meters: meters,
          sourceText: task.sourceText,
        ));
      }
    }

    return result;
  }

  // --- Zakres mmol: 3x800 (2-3 mmol) ---
  List<ZoneEntry> _evalMmolRange(ParsedTask task, String athlete, double mult) {
    final reps = (task.data['repetitions'] as int? ?? 0);
    final repDist = (task.data['repDist'] as double? ?? 0);
    final low = task.data['mmolLow'] as double? ?? 0;
    final high = task.data['mmolHigh'] as double? ?? 0;
    final totalDist = reps * repDist * mult;

    final splits = IntensityZone.splitByMmolRange(low, high, totalDist);
    return splits
        .where((s) => s.$2 > 0)
        .map((s) => ZoneEntry(
              athleteName: athlete,
              zone: s.$1,
              meters: s.$2,
              sourceText: task.sourceText,
            ))
        .toList();
  }

  // --- Selekcja powtórzeń: 10x200 (4-7-9-10zm mocno) ---
  List<ZoneEntry> _evalRepetitionSelection(ParsedTask task, String athlete, double mult) {
    final totalReps = task.data['totalReps'] as int? ?? 0;
    final repDist = (task.data['repDist'] as double? ?? 0);
    final selectedReps = task.data['selectedReps'] as List<int>? ?? [];
    final selectedZone = task.data['selectedZone'] as IntensityZone? ?? IntensityZone.en1;
    final baseZone = task.data['baseZone'] as IntensityZone? ?? IntensityZone.en1;

    final selectedCount = selectedReps.length;
    final baseCount = totalReps - selectedCount;

    return [
      if (selectedCount * repDist * mult > 0)
        ZoneEntry(
          athleteName: athlete,
          zone: selectedZone,
          meters: selectedCount * repDist * mult,
          sourceText: task.sourceText,
        ),
      if (baseCount * repDist * mult > 0)
        ZoneEntry(
          athleteName: athlete,
          zone: baseZone,
          meters: baseCount * repDist * mult,
          sourceText: task.sourceText,
        ),
    ];
  }

  // --- Podział stref w nawiasie: 4x250 (200tlen+50 95%) ---
  List<ZoneEntry> _evalSplitDistance(ParsedTask task, String athlete, double mult) {
    final reps = task.data['repetitions'] as int? ?? 0;
    final splits = task.data['splits'] as List<Map<String, dynamic>>? ?? [];

    final result = <ZoneEntry>[];
    for (final split in splits) {
      final meters = (split['meters'] as double? ?? 0) * reps * mult;
      final zone = split['zone'] as IntensityZone? ?? IntensityZone.en1;
      if (meters > 0) {
        result.add(ZoneEntry(
          athleteName: athlete,
          zone: zone,
          meters: meters,
          sourceText: task.sourceText,
        ));
      }
    }
    return result;
  }

  // --- Podział P-L / ćw.t-R ---
  List<ZoneEntry> _evalSplitZone(ParsedTask task, String athlete, double mult) {
    final total = (task.data['totalMeters'] as double? ?? 0) * mult;
    final zone1 = task.data['zone1'] as IntensityZone? ?? IntensityZone.en1;
    final fraction1 = task.data['fraction1'] as double? ?? 0.5;
    final zone2 = task.data['zone2'] as IntensityZone? ?? IntensityZone.rec;
    final fraction2 = task.data['fraction2'] as double? ?? 0.5;

    return [
      if (total * fraction1 > 0)
        ZoneEntry(athleteName: athlete, zone: zone1, meters: total * fraction1, sourceText: task.sourceText),
      if (total * fraction2 > 0)
        ZoneEntry(athleteName: athlete, zone: zone2, meters: total * fraction2, sourceText: task.sourceText),
    ];
  }
  // --- Compound Block: Nx(Mx<dist>+...) ---
  // multiplierOverride = TARGET outerMult dla tego zawodnika
  // (personalMod.multiplier to docelowy outerMult, nie mnożnik względny)
  List<ZoneEntry> _evalCompoundBlock(ParsedTask task, String athlete, double multiplierOverride) {
    final innerTotal = task.data['innerTotal'] as double? ?? 0;
    final zone = task.data['zone'] as IntensityZone? ?? IntensityZone.en1;
    final hasMixedZones = task.data['hasMixedZones'] as bool? ?? false;

    if (!hasMixedZones) {
      // Jednolita strefa – jeden wpis
      final total = multiplierOverride * innerTotal;
      if (total <= 0) return [];
      return [ZoneEntry(athleteName: athlete, zone: zone, meters: total, sourceText: task.sourceText)];
    } else {
      // Mixed zones per element wewnętrzny
      final innerBlocks = task.data['innerBlocks'] as List<Map<String, dynamic>>? ?? [];
      final result = <ZoneEntry>[];
      for (final block in innerBlocks) {
        final blockMeters = (block['meters'] as double? ?? 0) * multiplierOverride;
        final blockZone = block['zone'] as IntensityZone? ?? zone;
        if (blockMeters > 0) {
          result.add(ZoneEntry(
            athleteName: athlete,
            zone: blockZone,
            meters: blockMeters,
            sourceText: task.sourceText,
          ));
        }
      }
      return result;
    }
  }
}
