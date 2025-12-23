import 'package:flutter/material.dart';

class AiTutorHelpView extends StatelessWidget {
  const AiTutorHelpView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardBg = Color(0xFF1E243A);

    return Column(
      children: [
        // --- Ask Sesh Box ---
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tealAccent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: tealAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _circleIcon(Icons.auto_awesome),
                  const SizedBox(width: 15),
                  const Text("Ask Sesh AI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 15),
              const Text(
                "Get instant help with this question. Sesh can break down the problem, explain concepts, and guide you step-by-step.",
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              _fullWidthButton("Get Help from Sesh", isPrimary: true),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // --- Human Help Box ---
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Need Human Help?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text("Connect with a verified tutor who can explain this in detail", style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),
              _fullWidthButton("Find a Tutor", icon: Icons.person_add_alt_1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF00C09E).withValues(alpha: 0.1), shape: BoxShape.circle),
      child: const Icon(Icons.auto_awesome, color: Color(0xFF00C09E), size: 20),
    );
  }

  Widget _fullWidthButton(String label, {bool isPrimary = false, IconData? icon}) {
    const Color tealAccent = Color(0xFF00C09E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isPrimary ? tealAccent : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: isPrimary ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, color: Colors.white70, size: 18), const SizedBox(width: 8)],
          if (isPrimary) ...[const Icon(Icons.auto_awesome, color: Color(0xFF0F142B), size: 16), const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: isPrimary ? const Color(0xFF0F142B) : Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}