import 'package:flutter/material.dart';

class FriendCard extends StatelessWidget {
  final String name, id, year, streak, mins;
  final bool isOnline;
  final String presenceLabel;
  final VoidCallback onMessage;

  const FriendCard({
    super.key,
    required this.name,
    required this.id,
    required this.year,
    required this.streak,
    required this.mins,
    required this.isOnline,
    required this.presenceLabel,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    const Color scaffoldBg = Color(0xFF0F142B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardColor.withValues(alpha: 0.82),
            const Color(0xFF171D31).withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: tealAccent.withValues(alpha: 0.12),
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(
                    color: tealAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOnline ? tealAccent : Colors.white24,
                    shape: BoxShape.circle,
                    border: Border.all(color: scaffoldBg, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _statusBadge(presenceLabel, isOnline),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "$id • $year",
                  style: const TextStyle(color: Colors.white54, fontSize: 11.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricPill(
                      Icons.local_fire_department,
                      "$streak day streak",
                      const Color(0xFFF87171),
                    ),
                    _metricPill(Icons.timer_outlined, "$mins mins", tealAccent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text(
              "Chat",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: scaffoldBg,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String text, bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isOnline ? const Color(0xFF00C09E) : Colors.white24).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isOnline ? const Color(0xFF00C09E) : Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _metricPill(IconData icon, String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
