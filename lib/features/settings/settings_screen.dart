import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/design_system/app_colors.dart';
import '../../core/design_system/app_typography.dart';
import '../../features/athletes/athlete_repository.dart';
import '../../features/athletes/models/athlete.dart';

/// Ekran ustawień – zarządzanie zawodnikami
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _addAthlete(AthleteRepository repo) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    repo.addAthlete(name);
    _nameCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AthleteRepository>();
    final athletes = repo.athletes;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Ustawienia', style: AppTypography.headlineSm),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Sekcja zawodnicy ---
          _SectionHeader(title: 'Zawodnicy i Grupa', icon: Icons.group),
          const SizedBox(height: 12),

          // Pole dodawania
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  style: AppTypography.bodyLg,
                  decoration: InputDecoration(
                    hintText: 'Imię zawodnika...',
                    prefixIcon: const Icon(Icons.person_add_outlined, size: 20),
                  ),
                  onSubmitted: (_) => _addAthlete(repo),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _addAthlete(repo),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: const Icon(Icons.add, size: 20),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (athletes.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(Icons.group_off, size: 48, color: AppColors.outline),
                  const SizedBox(height: 8),
                  Text(
                    'Brak zawodników',
                    style: AppTypography.bodySm.copyWith(color: AppColors.outline),
                  ),
                ],
              ),
            ),

          ...athletes.map((athlete) => _AthleteCard(
                athlete: athlete,
                onToggleGroup: () => repo.toggleGroupMembership(athlete.id),
                onDelete: () => _confirmDelete(context, repo, athlete.id, athlete.name),
              )),

          const SizedBox(height: 24),

          // --- Legenda stref ---
          _SectionHeader(title: 'Legenda stref intensywności', icon: Icons.info_outline),
          const SizedBox(height: 12),
          _ZoneLegend(),

          const SizedBox(height: 24),

          // --- Słownik ---
          _SectionHeader(title: 'Słownik słów kluczowych', icon: Icons.book_outlined),
          const SizedBox(height: 12),
          _KeywordDictionary(),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    AthleteRepository repo,
    String id,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usuń zawodnika', style: AppTypography.headlineSm),
        content: Text(
          'Czy na pewno chcesz usunąć "$name"?',
          style: AppTypography.bodyLg,
        ),
        actions: [
          TextButton(
            child: Text('Anuluj', style: AppTypography.bodySm),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Usuń', style: AppTypography.bodySm.copyWith(color: Colors.white)),
            onPressed: () {
              repo.removeAthlete(id);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}

class _AthleteCard extends StatelessWidget {
  final Athlete athlete;
  final VoidCallback onToggleGroup;
  final VoidCallback onDelete;

  const _AthleteCard({
    required this.athlete,
    required this.onToggleGroup,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: athlete.isInGroup
              ? AppColors.primaryContainer.withValues(alpha: 0.5)
              : AppColors.surfaceContainerHigh,
          child: Text(
            athlete.name.isNotEmpty ? athlete.name[0].toUpperCase() : '?',
            style: AppTypography.headlineSm.copyWith(
              fontSize: 16,
              color: athlete.isInGroup ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
          ),
        ),
        title: Text(athlete.name, style: AppTypography.bodyLg),
        subtitle: Text(
          athlete.isInGroup ? 'W grupie' : 'Poza grupą',
          style: AppTypography.labelCaps.copyWith(
            color: athlete.isInGroup ? AppColors.secondary : AppColors.outline,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: athlete.isInGroup,
              onChanged: (_) => onToggleGroup(),
              activeThumbColor: AppColors.primary,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.error.withValues(alpha: 0.7)),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: AppTypography.labelCaps.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}

class _ZoneLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const zones = [
      ('Rec', '0–2.0 mmol/dm³', 'Regeneracja'),
      ('EN1', '2.1–3.5 mmol/dm³', 'Tlenowo'),
      ('EN2', '3.6–6.0 mmol/dm³', 'Progowo'),
      ('EN3', '6.1–8.0 mmol/dm³', 'VO2 max'),
      ('SP1', '>8.0 mmol/dm³', 'Szybkościowo 1'),
      ('SP2', 'max mmol / 95%', 'Szybkościowo 2'),
      ('SP3', 'Sprint maksymalny', 'Sprint'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: zones.asMap().entries.map((e) {
          final i = e.key;
          final zone = e.value;
          final bg = AppColors.zoneBg(zone.$1);
          final fg = AppColors.zoneFg(zone.$1);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: i < zones.length - 1
                  ? const Border(bottom: BorderSide(color: AppColors.outlineVariant))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    zone.$1,
                    style: AppTypography.labelCaps.copyWith(color: fg),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone.$3, style: AppTypography.bodySm),
                      Text(
                        zone.$2,
                        style: AppTypography.labelCaps.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _KeywordDictionary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const keywords = [
      ('Rec', 'rozpł, rozp, luz, ćw.t'),
      ('EN1', 'tlenowo, mocno, progres, progresja, regres, regresja'),
      ('EN2', 'progowo'),
      ('EN3', 'VO2 max, VO2max'),
      ('SP2', '95%'),
      ('SP3', 'spr, (O-A)'),
      ('EN1+Rec', 'P-L (50% EN1 + 50% Rec)'),
      ('Rec+EN1', 'ćw.t-R (50% Rec + 50% EN1)'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: keywords.asMap().entries.map((e) {
          final i = e.key;
          final kw = e.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: i % 2 == 0
                  ? AppColors.surfaceContainerLowest
                  : AppColors.surfaceContainerLow,
              border: i < keywords.length - 1
                  ? const Border(bottom: BorderSide(color: AppColors.outlineVariant))
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.zoneBg(kw.$1.split('+').first),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    kw.$1,
                    style: AppTypography.labelCaps.copyWith(
                        color: AppColors.zoneFg(kw.$1.split('+').first),
                        fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(kw.$2, style: AppTypography.dataMono.copyWith(fontSize: 12)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
