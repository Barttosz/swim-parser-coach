import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../../features/athletes/athlete_repository.dart';
import '../../features/athletes/models/athlete.dart';
import '../../features/parser/ast/parser.dart';
import '../../features/parser/evaluator/evaluator.dart';
import '../preflight/preflight_screen.dart';

class SessionInputScreen extends StatefulWidget {
  const SessionInputScreen({super.key});

  @override
  State<SessionInputScreen> createState() => _SessionInputScreenState();
}

class _SessionInputScreenState extends State<SessionInputScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _parse() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wklej notatki treningowe', style: AppTypography.bodySm),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final athleteRepo = context.read<AthleteRepository>();
    final parser = SwimParser(
      knownAthletes: athleteRepo.allNames,
      groupMembers: athleteRepo.groupMembers,
    );
    final evaluator = SwimEvaluator(groupMembers: athleteRepo.groupMembers);

    final session = parser.parseSession(text);
    final result = evaluator.evaluate(session);

    setState(() => _isLoading = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreflightScreen(
          parseResult: result,
          rawText: text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final athleteRepo = context.watch<AthleteRepository>();
    final athletes = athleteRepo.athletes;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.pool, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Parser Treningów', style: AppTypography.headlineSm),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Kalendarz',
            onPressed: () => Navigator.pushNamed(context, '/calendar'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ustawienia',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historia',
            onPressed: () => Navigator.pushNamed(context, '/history'),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Górny pasek z zawodnikami ---
          _AthletePresenceBar(athletes: athletes),

          const Divider(height: 1),

          // --- Pole tekstowe ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note,
                          color: AppColors.onSurfaceVariant, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Notatka trenerska',
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _focusNode.hasFocus
                              ? AppColors.chlorineTeal
                              : AppColors.outlineVariant,
                          width: _focusNode.hasFocus ? 2 : 1,
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: null,
                        expands: true,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.6,
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Wklej notatki treningowe...\n\nPrzykład:\nWika:\n12x100 progowo\n16x50 (20m spr)\n\nGrupa:\n2000 P-L',
                          hintStyle: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            color: AppColors.outline,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Licznik znaków
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_controller.text.length} znaków',
                      style: AppTypography.labelCaps.copyWith(
                        color: AppColors.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // --- Sticky bottom bar ---
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Zawodnicy: ${athletes.where((a) => a.isInGroup).length}/${athletes.length}',
                    style: AppTypography.labelCaps.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    _controller.text.isEmpty
                        ? 'Wklej notatkę i parsuj'
                        : '${_controller.text.split('\n').length} linii',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _parse,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  'Parsuj',
                  style: AppTypography.bodyLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pasek z checkboxami obecności zawodników
class _AthletePresenceBar extends StatelessWidget {
  final List<Athlete> athletes;

  const _AthletePresenceBar({required this.athletes});

  @override
  Widget build(BuildContext context) {
    if (athletes.isEmpty) {
      return Container(
        height: 48,
        color: AppColors.surfaceContainerLow,
        alignment: Alignment.center,
        child: Text(
          'Brak zawodników – dodaj w Ustawieniach',
          style: AppTypography.bodySm.copyWith(color: AppColors.outline),
        ),
      );
    }

    return Container(
      height: 52,
      color: AppColors.surfaceContainerLow,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: athletes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final athlete = athletes[i];
          final repo = context.read<AthleteRepository>();
          return FilterChip(
            label: Text(
              athlete.name,
              style: AppTypography.labelCaps.copyWith(
                color: athlete.isInGroup
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
            selected: athlete.isInGroup,
            onSelected: (_) => repo.toggleGroupMembership(athlete.id),
            selectedColor: AppColors.primaryContainer.withValues(alpha: 0.3),
            checkmarkColor: AppColors.primary,
            side: BorderSide(
              color: athlete.isInGroup ? AppColors.primary : AppColors.outlineVariant,
            ),
            backgroundColor: AppColors.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }
}
