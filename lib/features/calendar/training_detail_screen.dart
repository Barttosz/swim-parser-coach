import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../parser/models/intensity_zone.dart';
import '../parser/models/parse_result.dart';
import '../session/session_repository.dart';

class TrainingDetailScreen extends StatefulWidget {
  final TrainingSession session;
  final List<TrainingSession> allSessions;
  final String? athlete;

  const TrainingDetailScreen({
    super.key,
    required this.session,
    required this.allSessions,
    this.athlete,
  });

  @override
  State<TrainingDetailScreen> createState() => _TrainingDetailScreenState();
}

class _TrainingDetailScreenState extends State<TrainingDetailScreen>
    with SingleTickerProviderStateMixin {
  late TrainingSession _session;
  late AnimationController _headerAnim;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  // ── Edycja nazwy ─────────────────────────────────────────────
  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _session.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _NameDialog(controller: ctrl),
    );
    if (result != null && mounted) {
      await context
          .read<SessionRepository>()
          .updateSessionName(_session.id, result.trim());
    }
  }

  // ── Dodaj laktat ─────────────────────────────────────────────
  Future<void> _addLactate() async {
    final repo = context.read<SessionRepository>();
    final athletes = _session.athletes;
    if (athletes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Brak zawodników w tej sesji'),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    String selectedAthlete = athletes.first;
    final valueCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => _AddLactateDialog(
        athletes: athletes,
        selectedAthlete: selectedAthlete,
        controller: valueCtrl,
        onAdd: (athlete, value) async {
          await repo.addLactate(LactateEntry(
            sessionId: _session.id,
            athleteName: athlete,
            value: value,
            recordedAt: DateTime.now(),
          ));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SessionRepository>();
    _session =
        repo.sessions.where((s) => s.id == _session.id).firstOrNull ??
            _session;

    // Filtruj wpisy per zawodnik
    final athlete = widget.athlete;
    final filteredEntries = athlete != null
        ? _session.entries.where((e) => e.athleteName == athlete).toList()
        : _session.entries.toList();
    final athleteMeters = filteredEntries.fold(0.0, (s, e) => s + e.meters);
    final filteredLactates = athlete != null
        ? _session.lactates.where((l) => l.athleteName == athlete).toList()
        : _session.lactates.toList();

    final cum = athlete != null
        ? repo.cumulativeStatsForAthlete(_session.date, athlete)
        : repo.cumulativeStatsUpTo(_session.date);
    final hasName = _session.name.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero SliverAppBar ─────────────────────────────────
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppColors.primary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  size: 18, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 20, color: Colors.white70),
                tooltip: 'Zmień nazwę',
                onPressed: _editName,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _DetailHero(
                session: _session,
                athlete: athlete,
                athleteMeters: athleteMeters,
                filteredEntries: filteredEntries,
                hasName: hasName,
                onEditName: _editName,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.15)),
            ),
          ),

          // ── Treść ─────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Trening (per zawodnik)
                _SectionCard(
                  icon: Icons.pool_rounded,
                  label: athlete != null ? 'Trening – $athlete' : 'Trening',
                  accent: AppColors.primary,
                  trailing: _formatKm(athleteMeters),
                  child: _TrainingTable(
                    entries: filteredEntries,
                    totalMeters: athleteMeters,
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Narastające strefy dystansu (per zawodnik)
                _SectionCard(
                  icon: Icons.stacked_line_chart_rounded,
                  label: 'Narastające wg stref',
                  accent: AppColors.secondary,
                  trailing: athlete ?? 'do tego treningu',
                  child: _CumulativeDistanceTable(stats: cum),
                ),
                const SizedBox(height: 16),

                // 3. Laktaty (per zawodnik)
                _SectionCard(
                  icon: Icons.science_rounded,
                  label: athlete != null ? 'Laktaty – $athlete' : 'Laktaty',
                  accent: const Color(0xFF8D1B9E),
                  trailing: '${filteredLactates.length} pomiarów',
                  headerAction: _AddButton(onTap: _addLactate),
                  child: filteredLactates.isEmpty
                      ? _EmptyHint(
                          icon: Icons.science_outlined,
                          text: 'Brak pomiarów – dotknij + aby dodać')
                      : _LactateTable(
                          lactates: filteredLactates,
                          onDelete: (id) => repo.deleteLactate(id),
                        ),
                ),
                const SizedBox(height: 16),

                // 4. Narastające laktaty (per zawodnik)
                _SectionCard(
                  icon: Icons.analytics_rounded,
                  label: 'Narastające laktaty',
                  accent: AppColors.tertiary,
                  trailing: athlete ?? 'do tego treningu',
                  child: cum.allLactates.isEmpty
                      ? _EmptyHint(
                          icon: Icons.analytics_outlined,
                          text: 'Brak pomiarów laktatowych')
                      : _CumulativeLactateTable(stats: cum),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatKm(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.toStringAsFixed(0)} m';
  }
}

// ─────────────────────────────────────────────────────────────
// HERO HEADER
// ─────────────────────────────────────────────────────────────

class _DetailHero extends StatelessWidget {
  final TrainingSession session;
  final String? athlete;
  final double athleteMeters;
  final List<ZoneEntry> filteredEntries;
  final bool hasName;
  final VoidCallback onEditName;

  const _DetailHero({
    required this.session,
    required this.athlete,
    required this.athleteMeters,
    required this.filteredEntries,
    required this.hasName,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final dayName = DateFormat('EEEE', 'pl').format(session.date);
    final dateStr = DateFormat('d MMMM yyyy', 'pl').format(session.date);
    final km = athleteMeters / 1000;

    // Pasek stref w tle (per zawodnik)
    final Map<IntensityZone, double> zoneMap = {};
    for (final e in filteredEntries) {
      zoneMap[e.zone] = (zoneMap[e.zone] ?? 0) + e.meters;
    }
    final zones = zoneMap.entries
        .where((kv) => kv.value > 0)
        .map((kv) => (kv.key, kv.value))
        .toList();
    final barTotal = filteredEntries.fold(0.0, (s, e) => s + e.meters);

    return ClipRect(
      child: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF003E7A),
            Color(0xFF0055A4),
            Color(0xFF006A65),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Pasek stref per zawodnik
          if (zones.isNotEmpty && barTotal > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 4,
              child: Row(
                children: zones
                    .map((t) => Expanded(
                          flex: (t.$2 / barTotal * 1000)
                              .round()
                              .clamp(1, 1000),
                          child: Container(
                              color: AppColors.zoneBg(t.$1.label)
                                  .withValues(alpha: 0.8)),
                        ))
                    .toList(),
              ),
            ),

          // Treść – przypięta do dołu
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dzień tygodnia
                Text(
                  dayName[0].toUpperCase() + dayName.substring(1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryContainer.withValues(alpha: 0.9),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),

                // Data
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 6),

                // Nazwa sesji
                GestureDetector(
                  onTap: onEditName,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasName
                          ? AppColors.secondaryContainer
                              .withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: hasName
                            ? AppColors.secondaryContainer
                                .withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasName
                              ? Icons.label_rounded
                              : Icons.add_circle_outline,
                          size: 14,
                          color: hasName
                              ? AppColors.secondaryContainer
                              : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hasName ? session.name : 'Dodaj nazwę treningu...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: hasName
                                ? AppColors.secondaryContainer
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Km badge + athlete pill
                Row(
                  children: [
                    Text(
                      '${km.toStringAsFixed(2)} km',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (athlete != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          athlete!,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )); // ClipRect
  }
}

// ─────────────────────────────────────────────────────────────
// DIALOGI
// ─────────────────────────────────────────────────────────────

class _NameDialog extends StatelessWidget {
  final TextEditingController controller;
  const _NameDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.label_rounded, color: AppColors.secondary, size: 20),
          const SizedBox(width: 8),
          const Text('Nazwa treningu'),
        ],
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'np. Obóz Wisła, BPS, Zawody OW...',
          filled: true,
          fillColor: AppColors.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.secondary),
          ),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondary),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

class _AddLactateDialog extends StatefulWidget {
  final List<String> athletes;
  final String selectedAthlete;
  final TextEditingController controller;
  final Future<void> Function(String, double) onAdd;

  const _AddLactateDialog({
    required this.athletes,
    required this.selectedAthlete,
    required this.controller,
    required this.onAdd,
  });

  @override
  State<_AddLactateDialog> createState() => _AddLactateDialogState();
}

class _AddLactateDialogState extends State<_AddLactateDialog> {
  late String _athlete;

  @override
  void initState() {
    super.initState();
    _athlete = widget.selectedAthlete;
  }

  @override
  Widget build(BuildContext context) {
    final rawVal = widget.controller.text.replaceAll(',', '.');
    final val = double.tryParse(rawVal);
    final zone = val != null ? LactateZone.fromValue(val) : null;

    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.science_rounded,
              color: const Color(0xFF8D1B9E), size: 20),
          const SizedBox(width: 8),
          const Text('Pomiar laktatowy'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zawodnik
          DropdownButtonFormField<String>(
            value: _athlete,
            decoration: InputDecoration(
              labelText: 'Zawodnik',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.secondary)),
            ),
            items: widget.athletes
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: (v) => setState(() => _athlete = v!),
          ),
          const SizedBox(height: 12),

          // Wartość
          StatefulBuilder(
            builder: (ctx, setSt) => TextField(
              controller: widget.controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setSt(() {}),
              decoration: InputDecoration(
                labelText: 'mmol/L',
                hintText: 'np. 3.8',
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.secondary)),
                suffixIcon: zone != null
                    ? Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.zoneBg(zone.label),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          zone.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.zoneFg(zone.label),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),

          if (zone != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.zoneBg(zone.label),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${zone.label} · ${LactateZone.rangeLabel(zone)} mmol/L',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.zoneFg(zone.label),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj')),
        FilledButton(
          onPressed: () async {
            final v = double.tryParse(
                widget.controller.text.replaceAll(',', '.'));
            if (v == null) return;
            await widget.onAdd(_athlete, v);
            if (context.mounted) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondary),
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// KARTA SEKCJI
// ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final String? trailing;
  final Widget? headerAction;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.label,
    required this.accent,
    required this.child,
    this.trailing,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Nagłówek karty
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                  bottom: BorderSide(
                      color: accent.withValues(alpha: 0.15))),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: AppTypography.headlineSm.copyWith(
                      fontSize: 14, color: AppColors.onSurface),
                ),
                const Spacer(),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 10),
                  ),
                if (headerAction != null) ...[
                  const SizedBox(width: 8),
                  headerAction!,
                ],
              ],
            ),
          ),

          // Treść
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PRZYCISK DODAJ
// ─────────────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: AppColors.secondary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: AppColors.secondary),
            const SizedBox(width: 4),
            Text(
              'Dodaj',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TABELA TRENINGU
// ─────────────────────────────────────────────────────────────

class _TrainingTable extends StatelessWidget {
  final List<ZoneEntry> entries;
  final double totalMeters;

  const _TrainingTable({
    required this.entries,
    required this.totalMeters,
  });

  @override
  Widget build(BuildContext context) {
    // Grupuj po sourceText
    final Map<String, List<ZoneEntry>> bySource = {};
    for (final e in entries) {
      (bySource[e.sourceText] ??= []).add(e);
    }

    final rows = <Widget>[];

    for (final kv in bySource.entries) {
      final src = kv.key;
      final groupEntries = kv.value;

      // Grupuj po strefie
      final Map<String, double> zoneMeters = {};
      for (final e in groupEntries) {
        zoneMeters[e.zone.name] = (zoneMeters[e.zone.name] ?? 0) + e.meters;
      }

      bool isFirst = true;
      for (final zKv in zoneMeters.entries) {
        final zone = IntensityZone.values.firstWhere(
            (z) => z.name == zKv.key,
            orElse: () => IntensityZone.en1);
        rows.add(_TrainingRow(
          sourceText: isFirst ? src : null,
          meters: zKv.value,
          zone: zone,
          isFirst: isFirst,
        ));
        isFirst = false;
      }
    }

    return Column(
      children: [
        // Nagłówek
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: const [
              Expanded(flex: 7, child: _H('Zadanie')),
              Expanded(flex: 2, child: _H('m', right: true)),
              Expanded(flex: 2, child: _H('Strefa', right: true)),
            ],
          ),
        ),

        ...rows,

        // Suma
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.04),
            border: Border(
                top: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.15))),
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Expanded(flex: 8, child: SizedBox()),
              Expanded(
                flex: 4,
                child: Text(
                  'Σ ${_fmt(totalMeters)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.toStringAsFixed(0)} m';
  }
}

class _H extends StatelessWidget {
  final String text;
  final bool right;
  const _H(this.text, {this.right = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: right ? TextAlign.right : TextAlign.left,
      style: AppTypography.labelCaps
          .copyWith(color: AppColors.onSurfaceVariant, fontSize: 10),
    );
  }
}

class _TrainingRow extends StatelessWidget {
  final String? sourceText;
  final double meters;
  final IntensityZone zone;
  final bool isFirst;

  const _TrainingRow({
    required this.sourceText,
    required this.meters,
    required this.zone,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isFirst
            ? null
            : AppColors.surfaceContainerLow.withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(
              color: AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 7,
            child: sourceText != null
                ? Text(
                    sourceText!,
                    style: AppTypography.dataMono.copyWith(
                        fontSize: 11, color: AppColors.onSurface),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            flex: 2,
            child: Text(
              meters.toStringAsFixed(0),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _ZonePill(zone: zone),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NARASTAJĄCE STREFY DYSTANSU
// ─────────────────────────────────────────────────────────────

class _CumulativeDistanceTable extends StatelessWidget {
  final CumulativeStats stats;
  const _CumulativeDistanceTable({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.totalMeters;
    final zones = IntensityZone.values
        .where((z) => (stats.metersByZone[z] ?? 0) > 0)
        .toList();

    if (zones.isEmpty) {
      return _EmptyHint(icon: Icons.stacked_line_chart, text: 'Brak danych');
    }

    return Column(
      children: [
        // Nagłówek
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: const [
              Expanded(flex: 2, child: _H('Strefa')),
              SizedBox(width: 6),
              Expanded(flex: 2, child: _H('km', right: true)),
              SizedBox(width: 6),
              Expanded(flex: 1, child: _H('%', right: true)),
              SizedBox(width: 8),
              Expanded(flex: 4, child: _H('Rozkład')),
            ],
          ),
        ),

        ...zones.map((z) {
          final m = stats.metersByZone[z] ?? 0;
          final pct = total > 0 ? m / total : 0.0;
          return _CumDistRow(zone: z, meters: m, pct: pct);
        }),

        // Suma
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.04),
            border: Border(
                top: BorderSide(
                    color: AppColors.secondary.withValues(alpha: 0.2))),
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Łącznie ${total >= 1000 ? '${(total / 1000).toStringAsFixed(2)} km' : '${total.toStringAsFixed(0)} m'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CumDistRow extends StatelessWidget {
  final IntensityZone zone;
  final double meters;
  final double pct;

  const _CumDistRow(
      {required this.zone, required this.meters, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: _ZonePill(zone: zone)),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Text(
              (meters / 1000).toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: Text(
              '${(pct * 100).round()}%',
              textAlign: TextAlign.right,
              style: AppTypography.bodySm.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Stack(children: [
                Container(height: 8, color: AppColors.surfaceContainerHigh),
                FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  child: Container(
                      height: 8,
                      color: AppColors.zoneBorder(zone.label)),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TABELA LAKTATÓW
// ─────────────────────────────────────────────────────────────

class _LactateTable extends StatelessWidget {
  final List<LactateEntry> lactates;
  final ValueChanged<String> onDelete;
  const _LactateTable({required this.lactates, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Nagłówek
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: const [
              Expanded(flex: 3, child: _H('Zawodnik')),
              Expanded(flex: 2, child: _H('mmol/L', right: true)),
              SizedBox(width: 6),
              Expanded(flex: 2, child: _H('Strefa')),
              Expanded(flex: 2, child: _H('Czas')),
              SizedBox(width: 28),
            ],
          ),
        ),
        ...lactates.asMap().entries.map((e) => _LactateRow(
              lactate: e.value,
              isEven: e.key.isEven,
              onDelete: onDelete,
            )),
        Container(
          height: 4,
          decoration: const BoxDecoration(
            borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _LactateRow extends StatelessWidget {
  final LactateEntry lactate;
  final bool isEven;
  final ValueChanged<String> onDelete;

  const _LactateRow({
    required this.lactate,
    required this.isEven,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final zone = lactate.zone;
    final timeStr = DateFormat('HH:mm').format(lactate.recordedAt);

    return Container(
      decoration: BoxDecoration(
        color: isEven
            ? null
            : AppColors.surfaceContainerLow.withValues(alpha: 0.5),
        border: Border(
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.4))),
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(lactate.athleteName,
                style: AppTypography.bodySm
                    .copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text(
              lactate.value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.zoneFg(zone.label),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _ZonePill(zone: zone)),
          Expanded(
            flex: 2,
            child: Text(
              timeStr,
              style: AppTypography.bodySm.copyWith(
                  color: AppColors.onSurfaceVariant, fontSize: 11),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: AppColors.outline,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  title: const Text('Usuń pomiar?'),
                  content: Text(
                      '${lactate.athleteName}: ${lactate.value.toStringAsFixed(1)} mmol/L'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Anuluj')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onDelete(lactate.id);
                      },
                      child: Text('Usuń',
                          style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NARASTAJĄCE LAKTATY
// ─────────────────────────────────────────────────────────────

class _CumulativeLactateTable extends StatelessWidget {
  final CumulativeStats stats;
  const _CumulativeLactateTable({required this.stats});

  @override
  Widget build(BuildContext context) {
    final zones = LactateZone.displayZones
        .where((z) => stats.lactatesInZone(z).isNotEmpty)
        .toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: AppColors.surfaceContainerLow,
          child: Row(
            children: const [
              Expanded(flex: 2, child: _H('Strefa')),
              SizedBox(width: 6),
              Expanded(flex: 3, child: _H('Zakres mmol/L')),
              Expanded(flex: 2, child: _H('Szt.', right: true)),
              Expanded(flex: 2, child: _H('Średnia', right: true)),
            ],
          ),
        ),
        ...zones.asMap().entries.map((e) {
          final z = e.value;
          final count = stats.lactatesInZone(z).length;
          final avg = stats.avgLactateInZone(z);
          return _CumLactateRow(
            zone: z,
            count: count,
            avg: avg,
            isEven: e.key.isEven,
          );
        }),
        Container(
          height: 4,
          decoration: const BoxDecoration(
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(12))),
        ),
      ],
    );
  }
}

class _CumLactateRow extends StatelessWidget {
  final IntensityZone zone;
  final int count;
  final double avg;
  final bool isEven;

  const _CumLactateRow(
      {required this.zone,
      required this.count,
      required this.avg,
      required this.isEven});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isEven
            ? null
            : AppColors.surfaceContainerLow.withValues(alpha: 0.5),
        border: Border(
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 2, child: _ZonePill(zone: zone)),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: Text(
              LactateZone.rangeLabel(zone),
              style: AppTypography.bodySm.copyWith(
                  fontSize: 11, color: AppColors.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              avg.toStringAsFixed(2),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────

class _ZonePill extends StatelessWidget {
  final IntensityZone zone;
  const _ZonePill({required this.zone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.zoneBg(zone.label),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        zone.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: AppColors.zoneFg(zone.label),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.outline),
            ),
          ),
        ],
      ),
    );
  }
}
