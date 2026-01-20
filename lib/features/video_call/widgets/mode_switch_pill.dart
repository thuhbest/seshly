import 'package:flutter/material.dart';
import '../models/session_mode.dart';

class ModeSwitchPill extends StatelessWidget {
  final SessionMode currentMode;
  final Function(SessionMode) onChanged;

  const ModeSwitchPill({super.key, required this.currentMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTab("Teach", SessionMode.teach),
          _buildTab("Practice", SessionMode.practice),
          _buildTab("Review", SessionMode.review),
        ],
      ),
    );
  }

  Widget _buildTab(String label, SessionMode mode) {
    final bool isActive = currentMode == mode;
    return GestureDetector(
      onTap: () => onChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF00C09E) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? const Color(0xFF0F142B) : Colors.white54,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}