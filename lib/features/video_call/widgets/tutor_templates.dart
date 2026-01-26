import 'package:flutter/material.dart';

class TutorTemplates extends StatelessWidget {
  const TutorTemplates({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text("MY TEMPLATES", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        _templateItem("Calculus: Power Rule", "10 min • 5 Steps", tealAccent),
        _templateItem("Limits: Graph Interpretation", "15 min • Essay", Colors.purpleAccent),
        _templateItem("Integrals: Trig Sub", "20 min • Full Working", Colors.orangeAccent),
      ],
    );
  }

  Widget _templateItem(String title, String meta, Color accent) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: accent.withValues(alpha: 25), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.copy_rounded, color: accent, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(meta, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.rocket_launch_rounded, color: Color(0xFF00C09E), size: 18),
        ],
      ),
    );
  }
}
