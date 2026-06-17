import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../../core/utils/csv_exporter.dart';
import '../parser/models/intensity_zone.dart';
import '../parser/models/parse_result.dart';
import '../session/session_repository.dart';

// ─────────────────────────────────────────────────────────────
// MODELE STANOWE
// ─────────────────────────────────────────────────────────────

/// Jeden segment stref w ramach wariantu (np. 320m SP3)
class _ZoneSegment {
  IntensityZone zone;
  double meters;
  _ZoneSegment({required this.zone, required this.meters});

  String get fingerprint => '${zone.name}:${meters.toStringAsFixed(0)}';
}

/// Jeden slot zawodnika w wariancie (z flagą aktywności)
class _AthleteSlot {
  final String name;
  bool active;
  _AthleteSlot({required this.name, this.active = true});
}

/// Wariant zadania – grupuje zawodników z identycznym zestawem segmentów
class _TaskVariant {
  List<_AthleteSlot> slots;
  List<_ZoneSegment> segments;
  bool expanded; // czy lista checkboxów jest rozwinięta

  _TaskVariant({
    required this.slots,
    required this.segments,
    this.expanded = false,
  });

  List<String> get activeAthletes =>
      slots.where((s) => s.active).map((s) => s.name).toList();

  IntensityZone get dominantZone {
    if (segments.isEmpty) return IntensityZone.en1;
    return segments.reduce((a, b) => a.meters >= b.meters ? a : b).zone;
  }

  double get totalMeters =>
      segments.fold(0.0, (s, seg) => s + seg.meters);
}

/// Karta zadania – grupuje wszystkie warianty jednej linii źródłowej
class _TaskCard {
  final String sourceText;
  bool checked;
  List<_TaskVariant> variants;

  _TaskCard({
    required this.sourceText,
    required this.variants,
    this.checked = true,
  });

  IntensityZone get dominantZone =>
      variants.isEmpty ? IntensityZone.en1 : variants.first.dominantZone;
}

// ─────────────────────────────────────────────────────────────
// EKRAN GŁÓWNY
// ─────────────────────────────────────────────────────────────

class PreflightScreen extends StatefulWidget {
  final ParseResult parseResult;
  final String rawText;

  const PreflightScreen({
    super.key,
    required this.parseResult,
    required this.rawText,
  });

  @override
  State<PreflightScreen> createState() => _PreflightScreenState();
}

class _PreflightScreenState extends State<PreflightScreen> {
  late List<_TaskCard> _cards;
  bool _isSaving = false;
  DateTime _sessionDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _cards = _buildCards(widget.parseResult.entries);
  }

  // ── Budowanie kart ze spłaszczonej listy ZoneEntry ─────────

  static List<_TaskCard> _buildCards(List<ZoneEntry> entries) {
    // 1. Pogrupuj po sourceText (zachowując kolejność)
    final Map<String, List<ZoneEntry>> bySource = {};
    for (final e in entries) {
      (bySource[e.sourceText] ??= []).add(e);
    }

    return bySource.entries.map((kv) {
      final source = kv.key;
      final taskEntries = kv.value;

      // 2. Pogrupuj zawodników po zestawie segmentów (fingerprint)
      final Map<String, List<String>> fpAthletes = {}; // fp → [athletes]
      final Map<String, List<_ZoneSegment>> fpSegments = {}; // fp → segments

      final Map<String, List<ZoneEntry>> byAthlete = {};
      for (final e in taskEntries) {
        (byAthlete[e.athleteName] ??= []).add(e);
      }

      for (final athleteKv in byAthlete.entries) {
        final athlete = athleteKv.key;
        final aeList = athleteKv.value;

        // Fingerprint = posortowane "zone:meters"
        final segs = aeList
            .map((e) => _ZoneSegment(zone: e.zone, meters: e.meters))
            .toList();
        segs.sort((a, b) => b.meters.compareTo(a.meters)); // malejąco
        final fp = segs.map((s) => s.fingerprint).join('|');

        (fpAthletes[fp] ??= []).add(athlete);
        fpSegments[fp] = segs;
      }

      // 3. Zbuduj warianty (jeden per unikalny fingerprint)
      final variants = fpAthletes.entries.map((varKv) {
        final fp = varKv.key;
        final athletes = varKv.value;
        return _TaskVariant(
          slots: athletes.map((a) => _AthleteSlot(name: a)).toList(),
          segments: fpSegments[fp]!,
        );
      }).toList();

      return _TaskCard(sourceText: source, variants: variants);
    }).toList();
  }

  // ── Konwersja z powrotem do ZoneEntry ──────────────────────

  List<ZoneEntry> _toEntries() {
    final result = <ZoneEntry>[];
    for (final card in _cards) {
      if (!card.checked) continue;
      for (final variant in card.variants) {
        for (final slot in variant.slots) {
          if (!slot.active) continue;
          for (final seg in variant.segments) {
            result.add(ZoneEntry(
              athleteName: slot.name,
              zone: seg.zone,
              meters: seg.meters,
              sourceText: card.sourceText,
            ));
          }
        }
      }
    }
    return result;
  }

  // ── Obliczenia dla stopki ──────────────────────────────────

  double get _totalMeters {
    return _cards
        .where((c) => c.checked)
        .expand((c) => c.variants)
        .expand((v) => v.slots.where((s) => s.active).map((_) => v.totalMeters))
        .fold(0.0, (s, m) => s + m);
  }

  ParseResult get _currentResult => ParseResult(entries: _toEntries());

  // ── Zapis ─────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final repo = context.read<SessionRepository>();
      await repo.saveSession(TrainingSession(
        date: _sessionDate,
        rawText: widget.rawText,
        entries: _toEntries(),
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sesja zapisana!', style: AppTypography.bodySm),
          backgroundColor: AppColors.secondary,
        ));
        Navigator.popUntil(context, (r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Błąd: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _export() async {
    setState(() => _isSaving = true);
    try {
      final repo = context.read<SessionRepository>();
      await repo.saveSession(TrainingSession(
        date: _sessionDate,
        rawText: widget.rawText,
        entries: _toEntries(),
      ));
      await CsvExporter.exportAndShare(_currentResult, sessionDate: _sessionDate);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Błąd: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: _cards.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              itemCount: _cards.length,
              itemBuilder: (_, i) => _TaskCardWidget(
                card: _cards[i],
                taskNumber: i + 1,
                onRebuild: () => setState(() {}),
                onRemove: () => setState(() => _cards.removeAt(i)),
              ),
            ),
      bottomNavigationBar: _BottomBar(
        total: _totalMeters,
        result: _currentResult,
        isSaving: _isSaving,
        onSave: _save,
        onExport: _export,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final months = ['sty','lut','mar','kwi','maj','cze','lip','sie','wrz','paź','lis','gru'];
    final d = _sessionDate;
    final dateStr = '${d.day} ${months[d.month - 1]} ${d.year}';
    final checkedCount = _cards.where((c) => c.checked).length;

    return AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        color: AppColors.onSurface,
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wstępna Analiza Treningu',
              style: AppTypography.headlineSm.copyWith(fontSize: 15)),
          Text(dateStr,
              style: AppTypography.labelCaps
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 20),
          color: AppColors.onSurfaceVariant,
          tooltip: 'Zmień datę',
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _sessionDate,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
              locale: const Locale('pl'),
            );
            if (picked != null) setState(() => _sessionDate = picked);
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(34),
        child: Container(
          color: AppColors.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.secondary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Syntax Ready',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(width: 16),
              Icon(Icons.info_outline, size: 14, color: AppColors.outline),
              const SizedBox(width: 4),
              Text('$checkedCount zadań wykrytych',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off, size: 64, color: AppColors.outline),
          const SizedBox(height: 16),
          Text('Brak wyników parsowania',
              style: AppTypography.headlineSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────
// KARTA ZADANIA
// ─────────────────────────────────────────────────────────────

class _TaskCardWidget extends StatelessWidget {
  final _TaskCard card;
  final int taskNumber;
  final VoidCallback onRebuild;
  final VoidCallback onRemove;

  const _TaskCardWidget({
    required this.card,
    required this.taskNumber,
    required this.onRebuild,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.zoneBorder(card.dominantZone.label);

    return AnimatedOpacity(
      opacity: card.checked ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        // Stack zamiast IntrinsicHeight+Row – unika overflow przy animacji
        child: Stack(
          children: [
            // Lewy kolorowy pasek (Positioned – nie wymusza wysokości)
            Positioned(
              top: 0, bottom: 0, left: 0,
              width: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
            ),

            // Treść (z lewym marginesem 4px na pasek)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CardHeader(
                    card: card,
                    taskNumber: taskNumber,
                    onChecked: (v) {
                      card.checked = v;
                      onRebuild();
                    },
                    onRemove: onRemove,
                  ),

                  for (int i = 0; i < card.variants.length; i++) ...[
                    if (i > 0) const _VariantDivider(),
                    _VariantWidget(
                      variant: card.variants[i],
                      onRebuild: onRebuild,
                    ),
                  ],

                  const SizedBox(height: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NAGŁÓWEK KARTY
// ─────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final _TaskCard card;
  final int taskNumber;
  final ValueChanged<bool> onChecked;
  final VoidCallback onRemove;

  const _CardHeader({
    required this.card,
    required this.taskNumber,
    required this.onChecked,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox
          SizedBox(
            width: 20, height: 20,
            child: Checkbox(
              value: card.checked,
              onChanged: (v) => onChecked(v ?? true),
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
              side: const BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          const SizedBox(width: 8),

          // Tekst źródłowy + badge dominującej strefy
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '"${card.sourceText.length > 44 ? '${card.sourceText.substring(0, 42)}…' : card.sourceText}"',
                    style: AppTypography.dataMono.copyWith(
                        fontSize: 11, color: AppColors.onSurfaceVariant),
                  ),
                ),
                _ZoneBadge(zone: card.dominantZone),
              ],
            ),
          ),

          // Usuń
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
            color: AppColors.onSurfaceVariant,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Usuń zadanie',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SEPARATOR WARIANTÓW
// ─────────────────────────────────────────────────────────────

class _VariantDivider extends StatelessWidget {
  const _VariantDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Expanded(
              child: Divider(color: AppColors.outlineVariant, height: 1)),
          const SizedBox(width: 8),
          Text('inny wariant',
              style: AppTypography.labelCaps.copyWith(
                  color: AppColors.outline, fontSize: 10)),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(color: AppColors.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WARIANT ZADANIA
// ─────────────────────────────────────────────────────────────

class _VariantWidget extends StatelessWidget {
  final _TaskVariant variant;
  final VoidCallback onRebuild;

  const _VariantWidget({
    required this.variant,
    required this.onRebuild,
  });

  @override
  Widget build(BuildContext context) {
    final activeAthletes = variant.activeAthletes;
    final athleteLabel = activeAthletes.isEmpty
        ? '— brak —'
        : activeAthletes.length == 1
            ? activeAthletes.first
            : '${activeAthletes.first} +${activeAthletes.length - 1}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Wiersz: Athlete (dropdown) | Dystans | Strefa ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Athlete z rozwijalną listą checkboxów
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ATHLETE',
                        style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant, fontSize: 10)),
                    const SizedBox(height: 4),
                    // Chip – tap = toggle expand
                    GestureDetector(
                      onTap: () {
                        variant.expanded = !variant.expanded;
                        onRebuild();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(4),
                          border: variant.expanded
                              ? Border.all(color: AppColors.secondary)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                athleteLabel,
                                style: AppTypography.bodySm.copyWith(
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              variant.expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Rozwijalna lista checkboxów
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: variant.expanded
                          ? _AthleteCheckList(
                              slots: variant.slots,
                              onRebuild: onRebuild,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Segmenty (dystans + strefa)
              Expanded(
                flex: 7,
                child: _SegmentList(
                  variant: variant,
                  onRebuild: onRebuild,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA CHECKBOXÓW ZAWODNIKÓW
// ─────────────────────────────────────────────────────────────

class _AthleteCheckList extends StatelessWidget {
  final List<_AthleteSlot> slots;
  final VoidCallback onRebuild;

  const _AthleteCheckList({required this.slots, required this.onRebuild});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: slots.asMap().entries.map((e) {
          final i = e.key;
          final slot = e.value;
          return Column(
            children: [
              InkWell(
                onTap: () {
                  slot.active = !slot.active;
                  onRebuild();
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: Checkbox(
                          value: slot.active,
                          onChanged: (v) {
                            slot.active = v ?? true;
                            onRebuild();
                          },
                          activeColor: AppColors.secondary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3)),
                          side: const BorderSide(
                              color: AppColors.outlineVariant),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          slot.name,
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w500,
                            color: slot.active
                                ? AppColors.onSurface
                                : AppColors.outline,
                            decoration: slot.active
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (i < slots.length - 1)
                Divider(
                    height: 1,
                    color: AppColors.outlineVariant.withValues(alpha: 0.5)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LISTA SEGMENTÓW (Dystans + Strefa)
// ─────────────────────────────────────────────────────────────

class _SegmentList extends StatelessWidget {
  final _TaskVariant variant;
  final VoidCallback onRebuild;

  const _SegmentList({required this.variant, required this.onRebuild});

  @override
  Widget build(BuildContext context) {
    final segs = variant.segments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Nagłówki kolumn
        Row(
          children: [
            Expanded(
              flex: 4,
              child: Text('DYSTANS',
                  style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant, fontSize: 10)),
            ),
            Expanded(
              flex: 5,
              child: Text('STREFA',
                  style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onSurfaceVariant, fontSize: 10)),
            ),
            // miejsce na przycisk usuń
            const SizedBox(width: 28),
          ],
        ),
        const SizedBox(height: 4),

        // Każdy segment jako wiersz
        for (int i = 0; i < segs.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Icon(Icons.subdirectory_arrow_right,
                      size: 12, color: AppColors.outline),
                  const SizedBox(width: 2),
                  Expanded(
                      child: Divider(
                          height: 1, color: AppColors.outlineVariant)),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _SegmentRow(
                  segment: segs[i],
                  allZones: IntensityZone.values,
                  onRebuild: onRebuild,
                ),
              ),
              // Przycisk usuń (tylko gdy > 1 segment)
              if (segs.length > 1)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    onPressed: () {
                      segs.removeAt(i);
                      onRebuild();
                    },
                    icon: const Icon(Icons.close, size: 14),
                    color: AppColors.outline,
                    padding: EdgeInsets.zero,
                    tooltip: 'Usuń strefę',
                  ),
                )
              else
                const SizedBox(width: 28),
            ],
          ),
        ],

        // Pasek rozkładu stref (jeśli > 1 segment)
        if (segs.length > 1) ...[
          const SizedBox(height: 8),
          _DistributionBar(segments: segs),
        ],

        // Przycisk dodaj strefę
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () {
            segs.add(_ZoneSegment(zone: IntensityZone.en1, meters: 0));
            onRebuild();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline,
                  size: 13, color: AppColors.secondary),
              const SizedBox(width: 4),
              Text('Dodaj strefę',
                  style: AppTypography.labelCaps.copyWith(
                      color: AppColors.secondary, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WIERSZ SEGMENTU
// ─────────────────────────────────────────────────────────────

class _SegmentRow extends StatefulWidget {
  final _ZoneSegment segment;
  final List<IntensityZone> allZones;
  final VoidCallback onRebuild;

  const _SegmentRow({
    required this.segment,
    required this.allZones,
    required this.onRebuild,
  });

  @override
  State<_SegmentRow> createState() => _SegmentRowState();
}

class _SegmentRowState extends State<_SegmentRow> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.segment.meters.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Dystans (edytowalny)
        Expanded(
          flex: 4,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                      color: AppColors.primary,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 2),
                    ),
                    onChanged: (v) {
                      final m = double.tryParse(v);
                      if (m != null) {
                        seg.meters = m;
                        widget.onRebuild();
                      }
                    },
                  ),
                ),
                Text('m',
                    style: AppTypography.labelCaps.copyWith(
                        color: AppColors.outline, fontSize: 11)),
              ],
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Strefa (dropdown)
        Expanded(
          flex: 5,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.zoneBg(seg.zone.label)
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<IntensityZone>(
                value: seg.zone,
                isDense: true,
                isExpanded: true,
                icon: Icon(Icons.expand_more,
                    size: 14,
                    color: AppColors.zoneFg(seg.zone.label)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.zoneFg(seg.zone.label),
                ),
                selectedItemBuilder: (ctx) => widget.allZones
                    .map((z) => Align(
                          alignment: Alignment.centerLeft,
                          child: Text(z.label.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: AppColors.zoneFg(seg.zone.label),
                              )),
                        ))
                    .toList(),
                items: widget.allZones
                    .map((z) => DropdownMenuItem(
                          value: z,
                          child: Row(
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.zoneBorder(z.label),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(z.label,
                                  style: AppTypography.bodySm.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (z) {
                  if (z != null) {
                    seg.zone = z;
                    widget.onRebuild();
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PASEK ROZKŁADU STREF
// ─────────────────────────────────────────────────────────────

class _DistributionBar extends StatelessWidget {
  final List<_ZoneSegment> segments;
  const _DistributionBar({required this.segments});

  @override
  Widget build(BuildContext context) {
    final total = segments.fold(0.0, (s, seg) => s + seg.meters);
    if (total <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Int. Distribution',
            style: AppTypography.labelCaps.copyWith(
                color: AppColors.onSurfaceVariant, fontSize: 10)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 6,
            child: Row(
              children: segments
                  .map((seg) => Expanded(
                        flex: (seg.meters / total * 1000).round(),
                        child: Container(
                            color: AppColors.zoneBorder(seg.zone.label)),
                      ))
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 3),
        // Etykiety
        Row(
          children: segments
              .map((seg) => Expanded(
                    flex: (seg.meters / total * 1000).round(),
                    child: Text(
                      '${seg.meters.toStringAsFixed(0)}m ${seg.zone.label}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.zoneFg(seg.zone.label),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BADGE STREFY
// ─────────────────────────────────────────────────────────────

class _ZoneBadge extends StatelessWidget {
  final IntensityZone zone;
  const _ZoneBadge({required this.zone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.zoneBg(zone.label),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '${zone.label.toUpperCase()} · ${_name(zone)}',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: AppColors.zoneFg(zone.label),
        ),
      ),
    );
  }

  String _name(IntensityZone z) {
    switch (z) {
      case IntensityZone.rec: return 'RECOVERY';
      case IntensityZone.en1: return 'AEROBIC';
      case IntensityZone.en2: return 'THRESHOLD';
      case IntensityZone.en3: return 'VO2MAX';
      case IntensityZone.sp1: return 'SPEED 1';
      case IntensityZone.sp2: return 'SPEED 2';
      case IntensityZone.sp3: return 'SPRINT';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// STICKY BOTTOM BAR
// ─────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final double total;
  final ParseResult result;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onExport;

  const _BottomBar({
    required this.total,
    required this.result,
    required this.isSaving,
    required this.onSave,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    // Pasek stref
    final zones = IntensityZone.values;
    final fractions = total > 0
        ? zones
            .map((z) => (z, result.totalMetersInZone(z) / total))
            .where((t) => t.$2 > 0)
            .toList()
        : <(IntensityZone, double)>[];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fractions.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: fractions
                      .map((t) => Expanded(
                            flex: (t.$2 * 1000).round(),
                            child: Container(
                                color: AppColors.zoneBg(t.$1.label)),
                          ))
                      .toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('TOTAL DISTANCE',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Colors.white70)),
                  Text(
                    _fmt(total),
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'JetBrains Mono',
                        color: Colors.white),
                  ),
                ],
              ),
              const Spacer(),
              if (!isSaving)
                IconButton(
                  onPressed: onExport,
                  icon: const Icon(Icons.share,
                      color: Colors.white, size: 20),
                  tooltip: 'Eksport CSV',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              const SizedBox(width: 8),
              if (isSaving)
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
              else
                ElevatedButton.icon(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondaryContainer,
                    foregroundColor: AppColors.onSecondaryContainer,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text('ZATWIERDŹ',
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k m';
    }
    return '${v.toStringAsFixed(0)} m';
  }
}
