import 'package:flutter/material.dart';

class SeshAIPanel extends StatelessWidget {
  const SeshAIPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final Color tealAccent = const Color(0xFF00C09E);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Live Sesh AI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _aiToggle("Capture Board", true, tealAccent),
          const Divider(color: Colors.white10, height: 32),
          const Text("QUICK ACTIONS", style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 12),
          _aiActionButton(Icons.auto_awesome, "Summarise", tealAccent),
          _aiActionButton(Icons.search, "Spot Misconceptions", tealAccent),
        ],
      ),
    );
  }

  Widget _aiToggle(String label, bool value, Color teal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Switch(value: value, onChanged: (v) {}, activeColor: teal),
      ],
    );
  }

  Widget _aiActionButton(IconData icon, String label, Color teal) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white10),
          minimumSize: const Size(double.infinity, 45),
        ),
        onPressed: () {},
        icon: Icon(icon, size: 16, color: teal),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}