import 'package:flutter/material.dart';

class AchievementCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;

  const AchievementCard({super.key, required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00C09E).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF00C09E), size: 24),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(desc, 
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}