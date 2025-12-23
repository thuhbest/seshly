import 'package:flutter/material.dart';

class GoalsCard extends StatelessWidget {
  const GoalsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A), // Equivalent to Color(0xFF1E243A).withOpacity(0.5)
        borderRadius: BorderRadius.circular(15)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [Icon(Icons.track_changes, color: Color(0xFF00C09E), size: 20), SizedBox(width: 8), Text("Monthly Goals", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
              TextButton(
                onPressed: () {}, 
                child: const Text("+ Add Goal", style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12)) // Equivalent to Colors.white70
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF0F142B), 
              borderRadius: BorderRadius.circular(12)
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Improve Calculus marks from 60% → 75%", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    Text("53%", style: TextStyle(color: Color(0x88FFFFFF), fontSize: 12)), // Equivalent to Colors.white54
                  ],
                ),
                const SizedBox(height: 5),
                const Text("Current: 68% → Target: 75%", style: TextStyle(color: Color(0x61FFFFFF), fontSize: 11)), // Equivalent to Colors.white38
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5), 
                  child: const LinearProgressIndicator(
                    value: 0.53, 
                    backgroundColor: Color(0x1AFFFFFF), // Equivalent to Colors.white10
                    color: Color(0xFF00C09E), 
                    minHeight: 6
                  )
                ),
                const SizedBox(height: 12),
                const Text("Due: Nov 30, 2025", style: TextStyle(color: Color(0x61FFFFFF), fontSize: 11)), // Equivalent to Colors.white38
                const SizedBox(height: 10),
                _aiFeedback(),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _aiFeedback() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0D00C09E), // Equivalent to Color(0xFF00C09E).withOpacity(0.05)
        borderRadius: BorderRadius.circular(8), 
        border: Border.all(color: const Color(0x1A00C09E)) // Equivalent to Color(0xFF00C09E).withOpacity(0.1)
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, color: Color(0xFF00C09E), size: 14),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Sesh AI: Great progress! Focus on integration techniques this week. Practice 5 problems daily from Chapter 4.", 
              style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 11, fontStyle: FontStyle.italic) // Equivalent to Colors.white70
            )
          ),
        ],
      ),
    );
  }
}