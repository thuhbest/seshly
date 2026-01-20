import 'package:flutter/material.dart';

class AudioHighlights extends StatelessWidget {
  const AudioHighlights({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    final List<Map<String, String>> highlights = [
      {"time": "12:40", "topic": "Derivative Logic", "note": "Board Snapshot #4"},
      {"time": "24:15", "topic": "Common Sign Error", "note": "Nudge sent to Mike"},
      {"time": "38:10", "topic": "Final Summary", "note": "Shared Board Final"},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.waves_rounded, color: tealAccent, size: 20),
              const SizedBox(width: 10),
              const Text("AUDIO TIMESTAMPS", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 15),
          ...highlights.map((h) => _buildHighlightRow(h, tealAccent)),
        ],
      ),
    );
  }

  Widget _buildHighlightRow(Map<String, String> h, Color teal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(h["time"]!, style: TextStyle(color: teal, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h["topic"]!, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(h["note"]!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Icon(Icons.play_circle_outline_rounded, color: Colors.white.withValues(alpha: 50), size: 20),
        ],
      ),
    );
  }
}