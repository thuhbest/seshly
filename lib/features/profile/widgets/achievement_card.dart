import 'package:flutter/material.dart';

class AchievementCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  final bool isUnlocked; // 🔥 Added state to check if user earned it

  const AchievementCard({
    super.key, 
    required this.icon, 
    required this.title, 
    required this.desc,
    this.isUnlocked = true, // Default to true for now
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    
    return Container(
      padding: const EdgeInsets.all(15), // Using 15 from second version
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: isUnlocked ? 0.5 : 0.2),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isUnlocked ? Colors.white.withValues(alpha: 0.05) : Colors.transparent
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon container with background from second version
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (isUnlocked ? tealAccent : Colors.grey).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon, 
              color: isUnlocked ? tealAccent : Colors.white24, 
              size: 24 // Size from second version
            ),
          ),
          const SizedBox(height: 12), // Spacing from second version
          Text(
            title, 
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isUnlocked ? Colors.white : Colors.white24, 
              fontWeight: FontWeight.bold,
              fontSize: 13 // Font size from second version
            )
          ),
          const SizedBox(height: 4),
          Text(
            desc, 
            textAlign: TextAlign.center,
            style: TextStyle( // Removed const to avoid conflict
              color: Colors.white38, 
              fontSize: 10 // Font size from second version
            )
          ),
        ],
      ),
    );
  }
}