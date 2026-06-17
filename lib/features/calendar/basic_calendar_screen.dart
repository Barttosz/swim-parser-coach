import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../parser/models/intensity_zone.dart';
import '../parser/models/parse_result.dart';
import '../session/session_repository.dart';
import 'calendar_event_repository.dart';
import 'calendar_screen.dart'; // advanced calendar
import 'training_detail_screen.dart';

// ─────────────────────────────────────────────────────────────
// BASIC CALENDAR SCREEN
// ─────────────────────────────────────────────────────────────

class BasicCalendarScreen extends StatefulWidget {
  const BasicCalendarScreen({super.key});

  @override
  State<BasicCalendarScreen> createState() => _BasicCalendarScreenState();
}

class _BasicCalendarScreenState extends State<BasicCalendarScreen> {
  late DateTime _month; // Aktualnie wyświetlany miesiąc
  String? _selectedAthlete;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));
  void _nextMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1));

  String? _resolveAthlete(List<String> athletes) {
    if (athletes.isEmpty) return null;
    if (_selectedAthlete != null && athletes.contains(_selectedAthlete)) {
      return _selectedAthlete;
    }
    return athletes.first;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SessionRepository>();
    final eventRepo = context.watch<CalendarEventRepository>();
    final athletes = repo.allAthletes;
    final athlete = _resolveAthlete(athletes);

    if (athlete != null && _selectedAthlete != athlete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedAthlete = athlete);
      });
    }

    // Wszystkie sesje dla zawodnika
    final allSessions = athlete != null
        ? repo.sessionsForAthlete(athlete)
        : repo.sessions.toList();

    // Sesje w tym miesiącu
    final sessions = allSessions.where((s) {
      return s.date.year == _month.year && s.date.month == _month.month;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // Eventy tego miesiąca (dla phase labels)
    final events = eventRepo.events.where((e) {
      return e.date.year == _month.year && e.date.month == _month.month;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _AppBar(
            month: _month,
            athlete: athlete,
            athletes: athletes,
            onPrev: _prevMonth,
            onNext: _nextMonth,
            onAthleteChanged: (a) => setState(() => _selectedAthlete = a),
            onBack: () => Navigator.pop(context),
          ),

          // ── Phase labels (events tego miesiąca) ──────────────
          if (events.isNotEmpty)
            _PhaseLabels(events: events, eventRepo: eventRepo),

          // ── Lista treningów ──────────────────────────────────
          Expanded(
            child: sessions.isEmpty
                ? _EmptyMonth(month: _month)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    itemCount: _itemCount(sessions, athlete, repo),
                    itemBuilder: (ctx, i) => _buildItem(
                      ctx, i, sessions, athlete, allSessions, repo, eventRepo,
                    ),
                  ),
          ),
        ],
      ),

      // ── FAB przełączenia na kalendarz siatki ─────────────────
      floatingActionButton: _SwitchViewFab(month: _month),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // Oblicza całkowitą liczbę widgetów listy
  // (kafelki dni + rozdzielacze BPS + karta podsumowania)
  int _itemCount(
    List<TrainingSession> sessions,
    String? athlete,
    SessionRepository repo,
  ) {
    // 1 separator BPS per każdy event BPS w tym miesiącu
    // + sesje + 1 karta podsumowania tygodnia na końcu
    return sessions.length + 1; // +1 for weekly summary card
  }

  Widget? _buildItem(
    BuildContext ctx,
    int i,
    List<TrainingSession> sessions,
    String? athlete,
    List<TrainingSession> allSessions,
    SessionRepository repo,
    CalendarEventRepository eventRepo,
  ) {
    // Ostatni element = karta podsumowania
    if (i == sessions.length) {
      return _WeeklySummaryCard(
        sessions: sessions,
        athlete: athlete,
        month: _month,
      );
    }

    final session = sessions[i];

    // Sprawdź czy dzień przed tą sesją jest markerem BPS
    Widget? bpsMarker;
    if (i == 0 || sessions[i - 1].date.day != session.date.day) {
      // Szukaj markerów BPS tego dnia
      final bpsEvents = eventRepo.events.where((e) {
        final bpsStart = e.bpsStartDate;
        if (bpsStart == null) return false;
        return _sameDay(bpsStart, session.date);
      }).toList();
      if (bpsEvents.isNotEmpty) {
        bpsMarker = _BpsPhaseMarker(name: bpsEvents.first.name);
      }
    }

    // Sprawdź czy ta sesja jest w BPS
    final inBps = eventRepo.isInAnyBps(session.date);

    final widget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bpsMarker != null) bpsMarker,
        _DayItem(
          session: session,
          allSessions: allSessions,
          athlete: athlete,
          inBps: inBps,
          onTap: () => Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => TrainingDetailScreen(
                session: session,
                allSessions: allSessions,
                athlete: athlete,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );

    return widget;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────
// APP BAR (sticky header)
// ─────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final DateTime month;
  final String? athlete;
  final List<String> athletes;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<String> onAthleteChanged;
  final VoidCallback onBack;

  const _AppBar({
    required this.month,
    required this.athlete,
    required this.athletes,
    required this.onPrev,
    required this.onNext,
    required this.onAthleteChanged,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final monthStr = DateFormat('MMMM yyyy', 'pl').format(month);
    final capitalised =
        monthStr[0].toUpperCase() + monthStr.substring(1);

    return Container(
      color: AppColors.surfaceContainerLowest,
      child: Column(
        children: [
          // Status bar safe area
          SizedBox(height: MediaQuery.of(context).padding.top),

          // ── Rząd 1: zawodnik + athlete selector ──────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: AppColors.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Athlete name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aktywny zawodnik',
                        style: AppTypography.labelCaps.copyWith(
                            color: AppColors.onSurfaceVariant, fontSize: 10),
                      ),
                      Text(
                        athlete ?? 'Brak zawodników',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Athlete selector button
                if (athletes.length > 1)
                  _AthleteSelector(
                    athlete: athlete,
                    athletes: athletes,
                    onChanged: onAthleteChanged,
                  ),
              ],
            ),
          ),

          // ── Divider ──────────────────────────────────────────
          const Divider(height: 12, thickness: 0.5),

          // ── Rząd 2: nawigacja miesięcy ────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: AppColors.primary,
                  onPressed: onPrev,
                  tooltip: 'Poprzedni miesiąc',
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        capitalised,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.calendar_today_outlined,
                          size: 18, color: AppColors.onSurfaceVariant),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.primary,
                  onPressed: onNext,
                  tooltip: 'Następny miesiąc',
                ),
              ],
            ),
          ),

          Container(
            height: 1,
            color: AppColors.outlineVariant.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ATHLETE SELECTOR BUTTON
// ─────────────────────────────────────────────────────────────

class _AthleteSelector extends StatelessWidget {
  final String? athlete;
  final List<String> athletes;
  final ValueChanged<String> onChanged;

  const _AthleteSelector({
    required this.athlete,
    required this.athletes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Zawodnicy',
              style: AppTypography.labelCaps.copyWith(
                  color: AppColors.primary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: 20 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Wybierz zawodnika',
              style: AppTypography.headlineSm.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...athletes.map((a) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(a[0].toUpperCase(),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              title: Text(a,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              selected: a == athlete,
              selectedColor: AppColors.primary,
              selectedTileColor:
                  AppColors.primary.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              onTap: () {
                onChanged(a);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PHASE LABELS (scroll horizontal)
// ─────────────────────────────────────────────────────────────

class _PhaseLabels extends StatelessWidget {
  final List<dynamic> events;
  final CalendarEventRepository eventRepo;

  const _PhaseLabels({required this.events, required this.eventRepo});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: events.map<Widget>((e) {
            Color bg;
            Color fg = Colors.white;
            switch (e.type?.name) {
              case 'mainStart':
                bg = AppColors.primary;
                break;
              case 'secondaryStart':
                bg = AppColors.secondary;
                break;
              default:
                bg = AppColors.tertiary;
                fg = AppColors.onTertiary;
            }
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${e.type?.icon ?? '📌'} ${e.name}',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  letterSpacing: 0.3,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BPS PHASE MARKER
// ─────────────────────────────────────────────────────────────

class _BpsPhaseMarker extends StatelessWidget {
  final String name;
  const _BpsPhaseMarker({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
              child: Container(
                  height: 0.5,
                  color: AppColors.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Start BPS: $name',
              style: AppTypography.labelCaps.copyWith(
                  color: AppColors.onSurfaceVariant, fontSize: 10),
            ),
          ),
          Expanded(
              child: Container(
                  height: 0.5,
                  color: AppColors.outlineVariant)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DAY ITEM (kafelek treningu)
// ─────────────────────────────────────────────────────────────

class _DayItem extends StatelessWidget {
  final TrainingSession session;
  final List<TrainingSession> allSessions;
  final String? athlete;
  final bool inBps;
  final VoidCallback onTap;

  const _DayItem({
    required this.session,
    required this.allSessions,
    required this.athlete,
    required this.inBps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dayName = DateFormat('EEE', 'pl').format(session.date);
    final dayNum = session.date.day;

    // Per-athlete entries
    final entries = athlete != null
        ? session.entries.where((e) => e.athleteName == athlete).toList()
        : session.entries.toList();
    final meters = entries.fold(0.0, (s, e) => s + e.meters);

    // Kolor bocznego paska — bazując na fazie (BPS = secondary, inne = tertiary)
    final barColor = inBps ? AppColors.secondary : AppColors.tertiary;

    // Strefy do wyświetlenia jako kółka
    final Map<IntensityZone, double> zoneMap = {};
    for (final e in entries) {
      zoneMap[e.zone] = (zoneMap[e.zone] ?? 0) + e.meters;
    }
    final zones = zoneMap.keys.toList();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border.all(color: AppColors.outlineVariant, width: 0.8),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pasek fazy (lewa krawędź)
              Container(width: 4, color: barColor),

              // Data
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                        color: AppColors.outlineVariant, width: 0.8),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayName.toUpperCase(),
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '$dayNum',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),

              // Treść
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Nazwa sesji
                      Text(
                        session.name.isNotEmpty
                            ? session.name
                            : _defaultSessionName(entries),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Metry + kółka stref
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD5E3FF)
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _fmtMeters(meters),
                              style: const TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ...zones.map((z) => Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.zoneBorder(z.label),
                                  shape: BoxShape.circle,
                                ),
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Strzałka
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.outlineVariant,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _defaultSessionName(List<ZoneEntry> entries) {
    if (entries.isEmpty) return 'Trening';
    final zones = entries.map((e) => e.zone.label).toSet().join(' + ');
    return 'Trening ($zones)';
  }

  String _fmtMeters(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)}k';
    return '${m.toStringAsFixed(0)}m';
  }
}

// ─────────────────────────────────────────────────────────────
// WEEKLY SUMMARY CARD (na dole listy)
// ─────────────────────────────────────────────────────────────

class _WeeklySummaryCard extends StatelessWidget {
  final List<TrainingSession> sessions;
  final String? athlete;
  final DateTime month;

  const _WeeklySummaryCard({
    required this.sessions,
    required this.athlete,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final entries = sessions
        .expand((s) => athlete != null
            ? s.entries.where((e) => e.athleteName == athlete)
            : s.entries)
        .toList();

    final totalMeters = entries.fold(0.0, (s, e) => s + e.meters);
    final totalKm = totalMeters / 1000;

    // Rozkład stref
    final Map<IntensityZone, double> zoneMap = {};
    for (final e in entries) {
      zoneMap[e.zone] = (zoneMap[e.zone] ?? 0) + e.meters;
    }
    final zones = IntensityZone.values
        .where((z) => (zoneMap[z] ?? 0) > 0)
        .toList();

    // Numer tygodnia (ISO) miesiąca
    final monthName = DateFormat('MMMM', 'pl').format(month);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF003E7A), Color(0xFF0055A4), Color(0xFF006A65)],
          stops: [0.0, 0.6, 1.0],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF003E7A).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nagłówek
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Podsumowanie miesiąca',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                monthName[0].toUpperCase() + monthName.substring(1),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Statsy: km + liczba treningów
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'Dystans',
                  value: '${totalKm.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatBox(
                  label: 'Treningi',
                  value: '${sessions.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Intensity distribution bar
          if (totalMeters > 0) ...[
            Text(
              'ROZKŁAD INTENSYWNOŚCI',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: zones.map((z) {
                    final pct = (zoneMap[z] ?? 0) / totalMeters;
                    return Expanded(
                      flex: (pct * 1000).round().clamp(1, 1000),
                      child: Container(
                        color: AppColors.zoneBorder(z.label),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Legenda stref
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: zones.map((z) {
                final pct = totalMeters > 0
                    ? ((zoneMap[z] ?? 0) / totalMeters * 100)
                    : 0.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.zoneBorder(z.label),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${z.label} ${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0055A4).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────

class _EmptyMonth extends StatelessWidget {
  final DateTime month;
  const _EmptyMonth({required this.month});

  @override
  Widget build(BuildContext context) {
    final name = DateFormat('MMMM yyyy', 'pl').format(month);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pool_rounded,
              size: 48, color: AppColors.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'Brak treningów',
            style: AppTypography.headlineSm
                .copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            name[0].toUpperCase() + name.substring(1),
            style: AppTypography.bodySm
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FAB PRZEŁĄCZANIA NA WIDOK SIATKI
// ─────────────────────────────────────────────────────────────

class _SwitchViewFab extends StatelessWidget {
  final DateTime month;
  const _SwitchViewFab({required this.month});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'switch_to_grid',
      backgroundColor: AppColors.secondary,
      foregroundColor: Colors.white,
      elevation: 4,
      icon: const Icon(Icons.grid_view_rounded, size: 20),
      label: const Text(
        'Widok siatki',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CalendarScreen()),
      ),
    );
  }
}
