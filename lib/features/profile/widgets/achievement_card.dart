import 'package:flutter/material.dart';
import 'package:seshly/theme/seshly_theme.dart';

class AchievementCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool isUnlocked;

  const AchievementCard({
    super.key,
    required this.icon,
    required this.title,
    required this.desc,
    this.isUnlocked = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isUnlocked
        ? SeshlyPalette.gold.withValues(alpha: 0.28)
        : Colors.white.withValues(alpha: 0.05);
    final accent = isUnlocked ? SeshlyPalette.gold : SeshlyPalette.textMuted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isUnlocked
            ? const LinearGradient(
                colors: [Color(0xFF1C2135), Color(0xFF11263E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isUnlocked ? null : const Color(0xFF141C2D),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: isUnlocked
            ? [
                BoxShadow(
                  color: SeshlyPalette.gold.withValues(alpha: 0.08),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isUnlocked
                        ? [SeshlyPalette.gold, SeshlyPalette.rose]
                        : [
                            Colors.white.withValues(alpha: 0.08),
                            Colors.white.withValues(alpha: 0.03),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isUnlocked ? SeshlyPalette.background : Colors.white38,
                  size: 22,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isUnlocked
                      ? SeshlyPalette.gold.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isUnlocked ? 'Unlocked' : 'In Progress',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: isUnlocked ? Colors.white : Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
