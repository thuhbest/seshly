import 'package:flutter/material.dart';

class ArchiveView extends StatelessWidget {
  const ArchiveView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Your Study Archive", 
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
            ),
            // Interactive Badge with Clicking Effect
            ArchiveClickWrapper(
              onTap: () => debugPrint("View all notes"),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tealAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(15)
                ),
                child: const Text(
                  "35 notes", 
                  style: TextStyle(color: tealAccent, fontSize: 11, fontWeight: FontWeight.bold)
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        // --- Folders (Archive Items) ---
        _archiveFolder(Icons.architecture, "Mathematics", "12 notes", Colors.blueAccent),
        _archiveFolder(Icons.science_outlined, "Physics", "8 notes", Colors.purpleAccent),
        _archiveFolder(Icons.laptop_mac, "Computer Science", "15 notes", Colors.tealAccent),
      ],
    );
  }

  Widget _archiveFolder(IconData icon, String title, String count, Color accent) {
    return ArchiveClickWrapper(
      onTap: () => debugPrint("Opening $title Archive"),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E243A).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1), 
                borderRadius: BorderRadius.circular(12)
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(count, 
                    style: const TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// --- CLICK FEEDBACK WRAPPER ---
/// Adds the "Pressed" scale effect to all Archive buttons
class ArchiveClickWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const ArchiveClickWrapper({super.key, required this.child, required this.onTap});

  @override
  State<ArchiveClickWrapper> createState() => _ArchiveClickWrapperState();
}

class _ArchiveClickWrapperState extends State<ArchiveClickWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0, 
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}