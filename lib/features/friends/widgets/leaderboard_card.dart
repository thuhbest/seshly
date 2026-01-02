import 'package:flutter/material.dart';

class LeaderboardCard extends StatelessWidget {
  final int rank;
  final String name;
  final String streak;
  final bool isUser;

  const LeaderboardCard({
    super.key,
    required this.rank,
    required this.name,
    required this.streak,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    Color rankColor;
    switch (rank) {
      case 1: rankColor = const Color(0xFFFFD700); break; // Gold
      case 2: rankColor = const Color(0xFFC0C0C0); break; // Silver
      case 3: rankColor = const Color(0xFFCD7F32); break; // Bronze
      default: rankColor = Colors.white38;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFF00C09E).withValues(alpha: 0.1) : const Color(0xFF1E243A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isUser ? const Color(0xFF00C09E) : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Text(
            "#$rank",
            style: TextStyle(color: rankColor, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(width: 20),
          CircleAvatar(
            backgroundColor: rankColor.withValues(alpha: 0.2),
            child: Text(name[0], style: TextStyle(color: rankColor)),
          ),
          const SizedBox(width: 15),
          Text(
            name,
            style: TextStyle(
              color: isUser ? const Color(0xFF00C09E) : Colors.white,
              fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Colors.orangeAccent, size: 18),
              const SizedBox(width: 4),
              Text("$streak days", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}