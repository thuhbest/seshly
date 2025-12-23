import 'package:flutter/material.dart';

class TutorBanner extends StatelessWidget {
  const TutorBanner({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tealAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tealAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tealAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.school_outlined, color: tealAccent, size: 24),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Apply as a Tutor",
                  style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  "Share your knowledge and earn",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: tealAccent),
        ],
      ),
    );
  }
}