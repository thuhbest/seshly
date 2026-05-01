import 'package:flutter/material.dart';
import 'package:seshly/theme/seshly_theme.dart';

class LeaderboardCard extends StatelessWidget {
  final int rank;
  final String name;
  final int streak;
  final int xp;
  final String subtitle;
  final bool isUser;

  const LeaderboardCard({
    super.key,
    required this.rank,
    required this.name,
    required this.streak,
    required this.xp,
    required this.subtitle,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color rankColor = switch (rank) {
      1 => const Color(0xFFFFD670),
      2 => const Color(0xFFD8E0EB),
      3 => const Color(0xFFE4A56B),
      _ => SeshlyPalette.textMuted,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: isUser
            ? const LinearGradient(
                colors: [Color(0xFF14314D), Color(0xFF241F3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUser ? null : SeshlyPalette.surfaceRaised.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isUser
              ? SeshlyPalette.aqua.withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  rankColor.withValues(alpha: 0.95),
                  rankColor.withValues(alpha: 0.35),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: rank <= 3 ? SeshlyPalette.background : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isUser ? SeshlyPalette.aqua : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricPill(
                      icon: Icons.local_fire_department,
                      label: '$streak day streak',
                      accent: SeshlyPalette.rose,
                    ),
                    _MetricPill(
                      icon: Icons.auto_awesome,
                      label: '$xp XP',
                      accent: SeshlyPalette.gold,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: SeshlyPalette.aqua.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: SeshlyPalette.aqua,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}
