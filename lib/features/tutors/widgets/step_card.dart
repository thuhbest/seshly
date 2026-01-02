import 'package:flutter/material.dart';

class StepCard extends StatelessWidget {
  final String number, title, desc;

  const StepCard({super.key, required this.number, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tealAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(number, style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 18))),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }
}