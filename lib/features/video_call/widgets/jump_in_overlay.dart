import 'package:flutter/material.dart';

class JumpInOverlay extends StatelessWidget {
  final String studentName;
  final VoidCallback onExit;

  const JumpInOverlay({super.key, required this.studentName, required this.onExit});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [tealAccent.withValues(alpha: 200), Colors.transparent],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: Color(0xFF0F142B)),
            const SizedBox(width: 12),
            Text(
              "You are currently drawing on $studentName's board",
              style: const TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const Spacer(),
            TextButton(
              onPressed: onExit,
              style: TextButton.styleFrom(backgroundColor: const Color(0xFF0F142B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: const Text("Exit Intervention", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}