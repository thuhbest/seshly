import 'package:flutter/material.dart';

class ProgressStatCard extends StatefulWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const ProgressStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<ProgressStatCard> createState() => _ProgressStatCardState();
}

class _ProgressStatCardState extends State<ProgressStatCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E243A).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon with subtle glow background
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                widget.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}