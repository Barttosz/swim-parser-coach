import '../models/intensity_zone.dart';

/// Węzeł AST bazowy
abstract class AstNode {
  const AstNode();
}

/// Pojedynczy zestaw ćwiczeń: mnożnik × blok
class SetNode extends AstNode {
  final int multiplier;
  final AstNode block;
  final IntensityZone? zone;
  final List<PersonalMod> personalMods;
  final String sourceText;

  const SetNode({
    required this.multiplier,
    required this.block,
    this.zone,
    this.personalMods = const [],
    required this.sourceText,
  });
}

/// Prosty dystans w metrach
class DistanceNode extends AstNode {
  final double meters;
  final IntensityZone? zone;

  const DistanceNode({required this.meters, this.zone});
}

/// Blok złożony: kilka elementów połączonych "+"
class CompoundNode extends AstNode {
  final List<AstNode> children;
  final IntensityZone? zone;

  const CompoundNode({required this.children, this.zone});
}

/// Sprint w dystansie: "16x50 (20m spr)"
class SprintInDistanceNode extends AstNode {
  final int repetitions;
  final double totalRepDist;  // dystans całego powtórzenia (50m)
  final double sprintDist;    // dystans sprintu (20m)
  final String sourceText;

  const SprintInDistanceNode({
    required this.repetitions,
    required this.totalRepDist,
    required this.sprintDist,
    required this.sourceText,
  });
}

/// Podział dystansu z nawiasem: "4x250 (200tlen+50 95%)"
class SplitDistanceNode extends AstNode {
  final int repetitions;
  final List<(double, IntensityZone)> splits; // (metry, strefa)
  final String sourceText;

  const SplitDistanceNode({
    required this.repetitions,
    required this.splits,
    required this.sourceText,
  });
}

/// Podział cykliczny: "6x200 (6 cykli spr / 12 luz)"
class CyclicSplitNode extends AstNode {
  final int repetitions;
  final double totalDist;
  final List<(int, IntensityZone)> cycleGroups; // (cykle, strefa)
  final String sourceText;

  const CyclicSplitNode({
    required this.repetitions,
    required this.totalDist,
    required this.cycleGroups,
    required this.sourceText,
  });
}

/// Wtrącenie frakcyjne: "5x400 (w każdej 100-ce W 25 spr)"
class FractionalInsertNode extends AstNode {
  final int repetitions;
  final double repDist;           // 400m
  final double sectionSize;       // 100m (co tyle metrów...)
  final double sprintInSection;   // 25m sprint
  final IntensityZone insertZone; // SP3
  final IntensityZone baseZone;   // EN1
  final String sourceText;

  const FractionalInsertNode({
    required this.repetitions,
    required this.repDist,
    required this.sectionSize,
    required this.sprintInSection,
    required this.insertZone,
    required this.baseZone,
    required this.sourceText,
  });
}

/// Selekcja powtórzeń: "10x200 (4-7-9-10zm mocno)"
class RepetitionSelectionNode extends AstNode {
  final int totalReps;
  final double repDist;
  final List<int> selectedReps; // numery wybranych powtórzeń
  final IntensityZone selectedZone;
  final IntensityZone baseZone;
  final String sourceText;

  const RepetitionSelectionNode({
    required this.totalReps,
    required this.repDist,
    required this.selectedReps,
    required this.selectedZone,
    required this.baseZone,
    required this.sourceText,
  });
}

/// Zakres mmol: "3x800 (2-3 mmol)"
class MmolRangeNode extends AstNode {
  final int repetitions;
  final double repDist;
  final double mmolLow;
  final double mmolHigh;
  final String sourceText;

  const MmolRangeNode({
    required this.repetitions,
    required this.repDist,
    required this.mmolLow,
    required this.mmolHigh,
    required this.sourceText,
  });
}

/// Sesja – lista bloków z przypisaniem do zawodnika
class SessionNode extends AstNode {
  final List<AthleteBlock> blocks;

  const SessionNode({required this.blocks});
}

/// Blok zawodnika/grupy
class AthleteBlock extends AstNode {
  final List<String> athletes; // ["Wika"] lub ["Darul"] lub ["Wszystkie"] dla grupy
  final bool isGroup;
  final List<AstNode> tasks;

  const AthleteBlock({
    required this.athletes,
    required this.isGroup,
    required this.tasks,
  });
}

/// Modyfikator personalny w linii: "Wika 1x"
class PersonalMod {
  final String athleteName;
  final int multiplier;
  final double? overrideMeters;

  const PersonalMod({
    required this.athleteName,
    required this.multiplier,
    this.overrideMeters,
  });
}

/// Modyfikator P-L / ćw.t-R
class SplitZoneNode extends AstNode {
  final double totalMeters;
  final IntensityZone zone1;
  final double fraction1;
  final IntensityZone zone2;
  final double fraction2;
  final String sourceText;

  const SplitZoneNode({
    required this.totalMeters,
    required this.zone1,
    required this.fraction1,
    required this.zone2,
    required this.fraction2,
    required this.sourceText,
  });
}
