import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../../core/utils/csv_exporter.dart';
import '../../features/parser/models/intensity_zone.dart';
import '../../features/parser/models/parse_result.dart';
import '../../features/session/session_repository.dart';

/// Ekran historii sesji treningowych
class SessionHistoryScreen extends StatelessWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SessionRepository>();
    final sessions = repo.sessions;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Historia treningów', style: AppTypography.headlineSm),
      ),
      body: sessions.isEmpty
          ? _EmptyHistory()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, i) {
                final session = sessions[i];
                return _SessionCard(
                  session: session,
                  onDelete: () => _confirmDelete(context, repo, session.id),
                  onExport: () async {
                    final result = ParseResult(entries: session.entries);
                    await CsvExporter.exportAndShare(result, sessionDate: session.date);
                  },
                );
              },
            ),
    );
  }

  void _confirmDelete(BuildContext context, SessionRepository repo, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usuń sesję', style: AppTypography.headlineSm),
        content: Text('Czy na pewno usunąć tę sesję?', style: AppTypography.bodyLg),
        actions: [
          TextButton(
            child: const Text('Anuluj'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Usuń', style: TextStyle(color: Colors.white)),
            onPressed: () {
              repo.deleteSession(id);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final TrainingSession session;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _SessionCard({
    required this.session,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final result = ParseResult(entries: session.entries);
    final totalMeters = session.totalMeters;
    final dateStr = DateFormat('dd MMM yyyy', 'pl').format(session.date);

    // Dominująca strefa
    IntensityZone? dominantZone;
    double maxMeters = 0;
    for (final zone in IntensityZone.values) {
      final m = result.totalMetersInZone(zone);
      if (m > maxMeters) {
        maxMeters = m;
        dominantZone = zone;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          // Kolorowy pasek boczny + nagłówek
          IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: dominantZone != null
                        ? AppColors.zoneBorder(dominantZone.label)
                        : AppColors.outlineVariant,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 14, color: AppColors.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(dateStr,
                                style: AppTypography.labelCaps.copyWith(
                                    color: AppColors.primary)),
                            const Spacer(),
                            Text(
                              '${totalMeters.toStringAsFixed(0)} m',
                              style: AppTypography.dataMono.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Miniaturowy pasek stref
                        _MiniZoneBar(result: result, totalMeters: totalMeters),

                        const SizedBox(height: 8),

                        // Zawodnicy
                        Wrap(
                          spacing: 4,
                          children: session.athletes.map((a) {
                            return Chip(
                              label: Text(a,
                                  style: AppTypography.labelCaps.copyWith(
                                      color: AppColors.primary, fontSize: 10)),
                              backgroundColor:
                                  AppColors.primaryContainer.withValues(alpha: 0.2),
                              side: BorderSide.none,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Akcje
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: onExport,
                  icon: Icon(Icons.share, size: 16, color: AppColors.secondary),
                  label: Text('Eksport CSV',
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.secondary)),
                ),
              ),
              Container(width: 1, height: 32, color: AppColors.outlineVariant),
              Expanded(
                child: TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: AppColors.error),
                  label: Text('Usuń',
                      style: AppTypography.labelCaps.copyWith(
                          color: AppColors.error)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniZoneBar extends StatelessWidget {
  final ParseResult result;
  final double totalMeters;

  const _MiniZoneBar({required this.result, required this.totalMeters});

  @override
  Widget build(BuildContext context) {
    if (totalMeters <= 0) return const SizedBox.shrink();

    final fractions = IntensityZone.values
        .map((z) => (z, result.totalMetersInZone(z) / totalMeters))
        .where((t) => t.$2 > 0)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Row(
          children: fractions.map((t) {
            return Expanded(
              flex: (t.$2 * 1000).round(),
              child: Container(color: AppColors.zoneBg(t.$1.label)),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 72, color: AppColors.outline),
          const SizedBox(height: 16),
          Text(
            'Brak historii treningów',
            style: AppTypography.headlineSm.copyWith(
                color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Sparsuj i zatwierdź pierwszą sesję.',
            style: AppTypography.bodySm.copyWith(color: AppColors.outline),
          ),
        ],
      ),
    );
  }
}
