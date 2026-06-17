import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../parser/models/intensity_zone.dart';
import '../parser/models/parse_result.dart';
import '../session/session_repository.dart';
import 'calendar_event_repository.dart';
import 'training_detail_screen.dart';

// ─────────────────────────────────────────────────────────────
// STAŁE
// ─────────────────────────────────────────────────────────────

const _neonVolt = Color(0xFFB0DB00);
const _poolBlue = Color(0xFF003E7A);
const _teal = Color(0xFF006A65);

// ─────────────────────────────────────────────────────────────
// KALENDARZE – GŁÓWNY EKRAN
// ─────────────────────────────────────────────────────────────

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  // Endless scroll – generujemy tygodnie wokół dziś
  static const int _weeksBack = 52;
  static const int _weeksForward = 52;

  late final ScrollController _scrollCtrl;
  late final DateTime _today;
  late final DateTime _anchorMonday; // Poniedziałek bieżącego tygodnia
  String? _selectedAthlete; // null = pokaż wszystkich (tylko gdy brak zawodników)

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();
    _anchorMonday = _mondayOf(_today);
    _scrollCtrl = ScrollController();
    // Scroll do bieżącego tygodnia po build
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────

  DateTime _mondayOf(DateTime d) {
    return d.subtract(Duration(days: d.weekday - 1));
  }


  int get _totalWeeks => _weeksBack + 1 + _weeksForward;

  void _jumpToToday() {
    // Index środkowego tygodnia (dziś)
    const todayIdx = _weeksBack;
    // Szacowana wysokość tygodnia (nagłówek + 7 komórek + gap)
    const approxWeekHeight = 100.0;
    final offset = todayIdx * approxWeekHeight;
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(offset.clamp(0, _scrollCtrl.position.maxScrollExtent));
    }
  }

  void _animateToDate(DateTime date) {
    final monday = _mondayOf(date);
    final diffWeeks = monday.difference(_anchorMonday).inDays ~/ 7;
    final idx = _weeksBack + diffWeeks;
    if (idx < 0 || idx >= _totalWeeks) return;
    const approxWeekHeight = 100.0;
    final offset = idx * approxWeekHeight;
    _scrollCtrl.animateTo(
      offset.clamp(0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Athlete selector ───────────────────────────────────────

  String? _resolveAthlete(List<String> athletes) {
    if (athletes.isEmpty) return null;
    if (_selectedAthlete == null || !athletes.contains(_selectedAthlete)) {
      return athletes.first;
    }
    return _selectedAthlete;
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SessionRepository>();
    final eventRepo = context.watch<CalendarEventRepository>();
    final athletes = repo.allAthletes;
    final athlete = _resolveAthlete(athletes);

    // Synchronizuj _selectedAthlete
    if (athlete != null && _selectedAthlete != athlete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedAthlete = athlete);
      });
    }

    final sessions = athlete != null
        ? repo.sessionsForAthlete(athlete)
        : repo.sessions.toList();

    // Mapa dzień → sesja
    final sessionMap = <String, TrainingSession>{};
    for (final s in sessions) {
      sessionMap.putIfAbsent(_dayKey(s.date), () => s);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // ── Hero ──────────────────────────────────────
              _CalendarHero(
                today: _today,
                selectedAthlete: athlete,
                athletes: athletes,
                onAthleteChanged: (a) => setState(() => _selectedAthlete = a),
                onBack: () => Navigator.pop(context),
                onTodayTap: _jumpToToday,
              ),

              // ── Event countdown strip ─────────────────────
              _EventCountdownStrip(
                eventRepo: eventRepo,
                onDelete: (id) => eventRepo.deleteEvent(id),
              ),

              // ── Nagłówki dni ─────────────────────────────
              _WeekDayHeader(),

              // ── Endless scroll ────────────────────────────
              Expanded(
                child: _EndlessCalendarList(
                  scrollCtrl: _scrollCtrl,
                  weeksBack: _weeksBack,
                  weeksForward: _weeksForward,
                  anchorMonday: _anchorMonday,
                  today: _today,
                  sessionMap: sessionMap,
                  allSessions: sessions,
                  eventRepo: eventRepo,
                  athlete: athlete,
                ),
              ),
            ],
          ),

          // ── FAB: powrót do widoku listy ───────────────────────
          Positioned(
            right: 16,
            bottom: 24 + MediaQuery.of(context).padding.bottom,
            child: FloatingActionButton.extended(
              heroTag: 'switch_to_list',
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.view_list_rounded, size: 20),
              label: const Text(
                'Lista',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  static String _dayKey(DateTime d) => '${d.year}|${d.month}|${d.day}';
}

// ─────────────────────────────────────────────────────────────
// HERO – gradient header z athlete selector
// ─────────────────────────────────────────────────────────────

class _CalendarHero extends StatelessWidget {
  final DateTime today;
  final String? selectedAthlete;
  final List<String> athletes;
  final ValueChanged<String> onAthleteChanged;
  final VoidCallback onBack;
  final VoidCallback onTodayTap;

  const _CalendarHero({
    required this.today,
    required this.selectedAthlete,
    required this.athletes,
    required this.onAthleteChanged,
    required this.onBack,
    required this.onTodayTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.zero,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_poolBlue, Color(0xFF0055A4), _teal],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Nav row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        size: 18, color: Colors.white),
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onTodayTap,
                    style: TextButton.styleFrom(
                      foregroundColor: _neonVolt,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                    ),
                    child: Text('Dziś',
                        style: AppTypography.labelCaps.copyWith(
                            color: _neonVolt, fontSize: 12)),
                  ),
                ],
              ),
            ),

            // Athlete selector + label
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KALENDARZ TRENINGOWY',
                          style: AppTypography.labelCaps.copyWith(
                              color: Colors.white54, fontSize: 9)),
                      const SizedBox(height: 4),
                      Text('Zawodnik',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          )),
                    ],
                  ),
                  const Spacer(),
                  // Athlete dropdown
                  if (athletes.isNotEmpty)
                    _AthleteDropdown(
                      selected: selectedAthlete ?? athletes.first,
                      athletes: athletes,
                      onChanged: onAthleteChanged,
                    ),
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
// ATHLETE DROPDOWN
// ─────────────────────────────────────────────────────────────

class _AthleteDropdown extends StatelessWidget {
  final String selected;
  final List<String> athletes;
  final ValueChanged<String> onChanged;

  const _AthleteDropdown({
    required this.selected,
    required this.athletes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isDense: true,
          dropdownColor: AppColors.surfaceContainerLowest,
          icon: const Icon(Icons.expand_more, size: 16, color: Colors.white70),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          selectedItemBuilder: (ctx) => athletes
              .map((a) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(a,
                        style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ))
              .toList(),
          items: athletes
              .map((a) => DropdownMenuItem(
                    value: a,
                    child: Text(a,
                        style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w600)),
                  ))
              .toList(),
          onChanged: (a) { if (a != null) onChanged(a); },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// EVENT COUNTDOWN STRIP
// ─────────────────────────────────────────────────────────────

class _EventCountdownStrip extends StatelessWidget {
  final CalendarEventRepository eventRepo;
  final ValueChanged<String> onDelete;

  const _EventCountdownStrip({
    required this.eventRepo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final events = eventRepo.upcomingEvents;
    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      color: AppColors.surfaceContainerLow,
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        itemCount: events.length,
        separatorBuilder: (_, _x) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = events[i];
          final days = e.daysUntil();
          final label = days == 0
              ? 'Dziś!'
              : days == 1
                  ? 'Jutro'
                  : '$days dni';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: e.type == EventType.mainStart
                  ? _neonVolt.withValues(alpha: 0.15)
                  : AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: e.type == EventType.mainStart
                    ? _neonVolt
                    : AppColors.outlineVariant,
                width: e.type == EventType.mainStart ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.type.icon,
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(width: 4),
                Text(e.name,
                    style: AppTypography.bodySm.copyWith(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: e.type == EventType.mainStart
                        ? _neonVolt
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => onDelete(e.id),
                  child: Icon(Icons.close,
                      size: 12, color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NAGŁÓWKI DNI TYGODNIA
// ─────────────────────────────────────────────────────────────

class _WeekDayHeader extends StatelessWidget {
  static const _days = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: _days.asMap().entries.map((e) {
          final isWeekend = e.key >= 5;
          return Expanded(
            child: Text(
              e.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isWeekend
                    ? AppColors.secondary.withValues(alpha: 0.7)
                    : AppColors.onSurfaceVariant,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ENDLESS CALENDAR LIST
// ─────────────────────────────────────────────────────────────

class _EndlessCalendarList extends StatelessWidget {
  final ScrollController scrollCtrl;
  final int weeksBack;
  final int weeksForward;
  final DateTime anchorMonday;
  final DateTime today;
  final Map<String, TrainingSession> sessionMap;
  final List<TrainingSession> allSessions;
  final CalendarEventRepository eventRepo;
  final String? athlete;

  const _EndlessCalendarList({
    required this.scrollCtrl,
    required this.weeksBack,
    required this.weeksForward,
    required this.anchorMonday,
    required this.today,
    required this.sessionMap,
    required this.allSessions,
    required this.eventRepo,
    required this.athlete,
  });

  DateTime _weekAt(int offset) =>
      anchorMonday.add(Duration(days: offset * 7));

  static String _dayKey(DateTime d) => '${d.year}|${d.month}|${d.day}';

  @override
  Widget build(BuildContext context) {
    final totalWeeks = weeksBack + 1 + weeksForward;

    return ListView.builder(
      controller: scrollCtrl,
      itemCount: totalWeeks,
      cacheExtent: 1000,
      itemBuilder: (ctx, weekIdx) {
        final weekOffset = weekIdx - weeksBack;
        final monday = _weekAt(weekOffset);
        final sunday = monday.add(const Duration(days: 6));

        // Sprawdź czy to nowy miesiąc (insert month header)
        final showMonthHeader = monday.day <= 7 ||
            (weekIdx > 0 &&
                monday.month != _weekAt(weekOffset - 1).month);

        // Eventy tego tygodnia
        final weekEvents = eventRepo.eventsInWeek(monday);

        // BPS markers dla tego tygodnia
        final bpsStartInWeek = eventRepo.bpsEvents
            .where((e) {
              final bps = e.bpsStartDate;
              if (bps == null) return false;
              final bpsDay = DateTime(bps.year, bps.month, bps.day);
              return !bpsDay.isBefore(monday) && !bpsDay.isAfter(sunday);
            })
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nagłówek miesiąca
            if (showMonthHeader) _MonthHeader(date: monday),

            // BPS start banner (jeśli bps zaczyna się w tym tygodniu)
            if (bpsStartInWeek.isNotEmpty)
              _BpsStartBanner(events: bpsStartInWeek),

            // Tydzień (7 dni)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(7, (dayIdx) {
                  final day = monday.add(Duration(days: dayIdx));
                  final key = _dayKey(day);
                  final session = sessionMap[key];
                  final isToday = _sameDay(day, today);
                  final inBps = eventRepo.isInAnyBps(day);
                  final dayEvents = weekEvents
                      .where((e) => _sameDay(e.date, day))
                      .toList();

                  return Expanded(
                    child: _DayCell(
                      day: day,
                      isToday: isToday,
                      session: session,
                      allSessions: allSessions,
                      inBps: inBps,
                      events: dayEvents,
                      athlete: athlete,
                    ),
                  );
                }),
              ),
            ),

            // Gap między tygodniami z możliwością dodania eventu
            _WeekGap(
              afterWeekDate: sunday,
              eventRepo: eventRepo,
            ),
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ─────────────────────────────────────────────────────────────
// NAGŁÓWEK MIESIĄCA
// ─────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime date;
  const _MonthHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final rawLabel = DateFormat('LLLL yyyy', 'pl').format(date);
    final label = rawLabel[0].toUpperCase() + rawLabel.substring(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: AppColors.surfaceContainerLow.withValues(alpha: 0.5),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 0.2,
              )),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  height: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BPS START BANNER
// ─────────────────────────────────────────────────────────────

class _BpsStartBanner extends StatelessWidget {
  final List<CalendarEvent> events;
  const _BpsStartBanner({required this.events});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_poolBlue, _neonVolt],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            width: 3,
            height: 24,
            color: _neonVolt,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.flag_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'START BPS: ${events.map((e) => e.name).join(', ')}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.8,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WEEK GAP (między tygodniami z przyciskiem + dodania eventu)
// ─────────────────────────────────────────────────────────────

class _WeekGap extends StatefulWidget {
  final DateTime afterWeekDate; // Niedziela tygodnia
  final CalendarEventRepository eventRepo;

  const _WeekGap({required this.afterWeekDate, required this.eventRepo});

  @override
  State<_WeekGap> createState() => _WeekGapState();
}

class _WeekGapState extends State<_WeekGap> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _hovered = true),
      onTapCancel: () => setState(() => _hovered = false),
      behavior: HitTestBehavior.translucent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: _hovered ? 28 : 8,
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.4),
        child: _hovered
            ? Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _hovered = false);
                    _showAddEventSheet(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text('Dodaj wydarzenie',
                            style: AppTypography.labelCaps
                                .copyWith(color: Colors.white, fontSize: 9)),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  void _showAddEventSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddEventSheet(
        date: widget.afterWeekDate.add(const Duration(days: 1)), // Poniedziałek
        eventRepo: widget.eventRepo,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ADD EVENT BOTTOM SHEET
// ─────────────────────────────────────────────────────────────

class _AddEventSheet extends StatefulWidget {
  final DateTime date;
  final CalendarEventRepository eventRepo;

  const _AddEventSheet({required this.date, required this.eventRepo});

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  EventType? _selectedType;
  int _bpsWeeks = 8;
  bool _askBps = true;
  final _nameCtrl = TextEditingController();
  DateTime? _eventDate;

  @override
  void initState() {
    super.initState();
    _eventDate = widget.date;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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

          Text('Dodaj wydarzenie',
              style: AppTypography.headlineSm),
          const SizedBox(height: 4),

          // Date picker row
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _eventDate!,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                locale: const Locale('pl'),
              );
              if (picked != null) setState(() => _eventDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('d MMMM yyyy', 'pl').format(_eventDate!),
                    style: AppTypography.bodySm
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(Icons.edit, size: 14, color: AppColors.outline),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Typ eventu
          if (_selectedType == null) ...[
            Text('Typ wydarzenia:',
                style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 10),
            ...EventType.values.map((t) => _EventTypeButton(
                  type: t,
                  onTap: () => setState(() => _selectedType = t),
                )),
          ] else ...[
            // Nazwa
            Text('NAZWA',
                style: AppTypography.labelCaps.copyWith(
                    color: AppColors.onSurfaceVariant, fontSize: 10)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: AppTypography.bodySm
                  .copyWith(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '${_selectedType!.icon} ${_selectedType!.label}...',
                hintStyle: AppTypography.bodySm
                    .copyWith(color: AppColors.outline),
                filled: true,
                fillColor: AppColors.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 16),

            // BPS dialog (tylko dla mainStart / secondaryStart)
            if (_selectedType!.hasBps) ...[
              Row(
                children: [
                  Checkbox(
                    value: _askBps,
                    onChanged: (v) => setState(() => _askBps = v ?? true),
                    activeColor: AppColors.secondary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  Text('Określ BPS dla tego startu',
                      style: AppTypography.bodySm),
                ],
              ),
              if (_askBps) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('$_bpsWeeks tyg.',
                        style: AppTypography.dataMono.copyWith(
                            color: _neonVolt,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('przed startem',
                        style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant)),
                    const Spacer(),
                    Text(
                      _bpsWeeks > 0
                          ? DateFormat('d MMM', 'pl').format(
                              _eventDate!.subtract(
                                  Duration(days: _bpsWeeks * 7)))
                          : '',
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.secondary, fontSize: 10),
                    ),
                  ],
                ),
                Slider(
                  value: _bpsWeeks.toDouble(),
                  min: 4,
                  max: 16,
                  divisions: 12,
                  activeColor: _neonVolt,
                  inactiveColor: AppColors.outlineVariant,
                  label: '$_bpsWeeks tyg.',
                  onChanged: (v) => setState(() => _bpsWeeks = v.round()),
                ),
              ],
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selectedType = null),
                  child: Text('Wróć',
                      style: AppTypography.bodySm.copyWith(
                          color: AppColors.outline)),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _nameCtrl.text.trim().isEmpty ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Dodaj'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final event = CalendarEvent(
      date: _eventDate!,
      type: _selectedType!,
      name: name,
      bpsWeeks: (_selectedType!.hasBps && _askBps) ? _bpsWeeks : null,
    );
    await widget.eventRepo.addEvent(event);
    if (mounted) Navigator.pop(context);
  }
}

class _EventTypeButton extends StatelessWidget {
  final EventType type;
  final VoidCallback onTap;

  const _EventTypeButton({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(type.icon,
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label,
                        style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w700)),
                    if (type.hasBps)
                      Text('Możliwość ustawienia BPS',
                          style: AppTypography.labelCaps.copyWith(
                              color: _neonVolt, fontSize: 9)),
                  ],
                ),
                const Spacer(),
                Icon(Icons.chevron_right,
                    color: AppColors.outline, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// KOMÓRKA DNIA
// ─────────────────────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final TrainingSession? session;
  final List<TrainingSession> allSessions;
  final bool inBps;
  final List<CalendarEvent> events;
  final String? athlete; // Wybrany zawodnik

  const _DayCell({
    required this.day,
    required this.isToday,
    required this.session,
    required this.allSessions,
    required this.inBps,
    required this.events,
    required this.athlete,
  });

  @override
  Widget build(BuildContext context) {
    final hasSession = session != null;
    final hasEvent = events.isNotEmpty;

    // Filtrow dane per zawodnik
    final athleteEntries = session != null && athlete != null
        ? session!.entries.where((e) => e.athleteName == athlete).toList()
        : session?.entries.toList() ?? [];
    final athleteMeters = athleteEntries.fold(0.0, (s, e) => s + e.meters);

    Color bg = AppColors.background;
    if (hasSession) bg = AppColors.surfaceContainerLowest;
    if (inBps) {
      bg = Color.lerp(bg, _neonVolt, 0.04)!;
    }

    return GestureDetector(
      onTap: hasSession
          ? () => Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, a1, a2) => TrainingDetailScreen(
                    session: session!,
                    allSessions: allSessions,
                    athlete: athlete,
                  ),
                  transitionsBuilder: (_, anim, __, child) => SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(1, 0), end: Offset.zero)
                        .animate(CurvedAnimation(
                            parent: anim, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
              )
          : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            left: BorderSide(
              color: inBps
                  ? _neonVolt.withValues(alpha: 0.6)
                  : AppColors.outlineVariant.withValues(alpha: 0.3),
              width: inBps ? 2 : 0.5,
            ),
            right: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
                width: 0.5),
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
                width: 0.5),
            bottom: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3),
                width: 0.5),
          ),
        ),
        child: Stack(
          children: [
            // Kolorowy pasek stref (lewa krawędź sesji)
            if (hasSession && !inBps)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: _zoneGradient(athleteEntries),
                    ),
                  ),
                ),
              ),

            Padding(
              padding: EdgeInsets.fromLTRB(
                  (hasSession && !inBps) ? 6 : 4, 3, 3, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Numer dnia
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: isToday
                          ? BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                            )
                          : null,
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: isToday
                              ? Colors.white
                              : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),

                  if (hasEvent) ...[
                    const SizedBox(height: 2),
                    ...events.map((e) => Text(
                          '${e.type.icon}',
                          style: const TextStyle(fontSize: 10),
                        )),
                  ],

                  if (hasSession) ...[
                    const SizedBox(height: 3),
                    _MiniZoneBar(entries: athleteEntries),
                    const SizedBox(height: 4),
                    Text(
                      _fmtMeters(athleteMeters),
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    if (session!.name.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        session!.name,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Color> _zoneGradient(List<ZoneEntry> entries) {
    final Map<IntensityZone, double> zoneMap = {};
    for (final e in entries) {
      zoneMap[e.zone] = (zoneMap[e.zone] ?? 0) + e.meters;
    }
    final zones = zoneMap.keys.toList();
    if (zones.isEmpty) return [AppColors.outline];
    if (zones.length == 1) {
      final c = AppColors.zoneBorder(zones.first.label);
      return [c, c];
    }
    return zones.map((z) => AppColors.zoneBorder(z.label)).toList();
  }

  String _fmtMeters(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)}k';
    return '${m.toStringAsFixed(0)}m';
  }
}

// ─────────────────────────────────────────────────────────────
// MINI PASEK STREF
// ─────────────────────────────────────────────────────────────

class _MiniZoneBar extends StatelessWidget {
  final List<ZoneEntry> entries;
  const _MiniZoneBar({required this.entries});

  @override
  Widget build(BuildContext context) {
    final Map<IntensityZone, double> zoneMap = {};
    for (final e in entries) {
      zoneMap[e.zone] = (zoneMap[e.zone] ?? 0) + e.meters;
    }
    final total = zoneMap.values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return const SizedBox.shrink();

    final zones = zoneMap.entries
        .where((kv) => kv.value > 0)
        .map((kv) => (kv.key, kv.value))
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 5,
        child: Row(
          children: zones
              .map((t) => Expanded(
                    flex: (t.$2 / total * 1000).round().clamp(1, 1000),
                    child:
                        Container(color: AppColors.zoneBorder(t.$1.label)),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MINI CALENDAR SHEET (zoom-out)
// ─────────────────────────────────────────────────────────────

class _MiniCalendarSheet extends StatefulWidget {
  final List<TrainingSession> sessions;
  final CalendarEventRepository eventRepo;
  final DateTime today;
  final ValueChanged<DateTime> onDayTapped;

  const _MiniCalendarSheet({
    required this.sessions,
    required this.eventRepo,
    required this.today,
    required this.onDayTapped,
  });

  @override
  State<_MiniCalendarSheet> createState() => _MiniCalendarSheetState();
}

class _MiniCalendarSheetState extends State<_MiniCalendarSheet> {
  late DateTime _viewMonth;
  late Map<String, TrainingSession> _sessionMap;

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime(widget.today.year, widget.today.month, 1);
    _buildSessionMap();
  }

  void _buildSessionMap() {
    _sessionMap = {};
    for (final s in widget.sessions) {
      _sessionMap.putIfAbsent(_dayKey(s.date), () => s);
    }
  }

  static String _dayKey(DateTime d) => '${d.year}|${d.month}|${d.day}';
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Navigation
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _viewMonth = DateTime(
                        _viewMonth.year, _viewMonth.month - 1, 1);
                  }),
                ),
                Expanded(
                  child: Text(
                    () {
                      final raw = DateFormat('LLLL yyyy', 'pl').format(_viewMonth);
                      return raw[0].toUpperCase() + raw.substring(1);
                    }(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                    _viewMonth = DateTime(
                        _viewMonth.year, _viewMonth.month + 1, 1);
                  }),
                ),
              ],
            ),
          ),

          // Day headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: ['Pn','Wt','Śr','Cz','Pt','So','Nd']
                  .asMap()
                  .entries
                  .map((e) => Expanded(
                        child: Text(
                          e.value,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: e.key >= 5
                                ? AppColors.secondary.withValues(alpha: 0.6)
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),

          // Calendar grid
          Expanded(
            child: _buildMiniGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniGrid() {
    final firstDay = _viewMonth;
    final weekdayOfFirst = firstDay.weekday;
    final gridStart = firstDay.subtract(Duration(days: weekdayOfFirst - 1));
    final lastDay = DateTime(_viewMonth.year, _viewMonth.month + 1, 0);
    final weekdayOfLast = lastDay.weekday;
    final gridEnd = weekdayOfLast == 7
        ? lastDay
        : lastDay.add(Duration(days: 7 - weekdayOfLast));

    final days = <DateTime>[];
    for (var d = gridStart; !d.isAfter(gridEnd); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    final rows = (days.length / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: List.generate(rows, (row) {
          return Expanded(
            child: Row(
              children: List.generate(7, (col) {
                final idx = row * 7 + col;
                if (idx >= days.length) return const Expanded(child: SizedBox());
                final day = days[idx];
                final inMonth = day.month == _viewMonth.month;
                final isToday = _sameDay(day, widget.today);
                final hasSession = _sessionMap.containsKey(_dayKey(day));
                final inBps = widget.eventRepo.isInAnyBps(day);
                final hasEvent = widget.eventRepo.eventsInMonth(day.year, day.month)
                    .any((e) => _sameDay(e.date, day));

                return Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onDayTapped(day),
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.primary
                            : inBps
                                ? _neonVolt.withValues(alpha: 0.12)
                                : hasSession
                                    ? AppColors.surfaceContainerLow
                                    : null,
                        borderRadius: BorderRadius.circular(4),
                        border: hasEvent
                            ? Border.all(color: _neonVolt, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isToday || hasSession
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                              color: isToday
                                  ? Colors.white
                                  : inMonth
                                      ? AppColors.onSurface
                                      : AppColors.outline.withValues(alpha: 0.4),
                            ),
                          ),
                          if (hasSession)
                            Container(
                              width: 4, height: 4,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : AppColors.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}
