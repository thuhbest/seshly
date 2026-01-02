import 'package:flutter/material.dart';
import '../widgets/vault_card.dart';
import '../widgets/contribution_stats.dart';

class VaultView extends StatefulWidget {
  const VaultView({super.key});

  @override
  State<VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<VaultView> {
  bool isAllMaterials = true;

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header Section ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Study Vault", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Community-shared materials verified by Sesh", 
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            VaultActionButton(
              onTap: () => debugPrint("Upload Clicked"),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: tealAccent, borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.upload_outlined, size: 18, color: backgroundColor),
                    SizedBox(width: 8),
                    Text("Upload", style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        // --- Toggle Buttons ---
        Row(
          children: [
            _toggleBtn("All Materials", isAllMaterials, () => setState(() => isAllMaterials = true)),
            const SizedBox(width: 12),
            _toggleBtn("My Uploads (3)", !isAllMaterials, () => setState(() => isAllMaterials = false)),
          ],
        ),
        const SizedBox(height: 30),

        // --- Dynamic Content Section ---
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isAllMaterials ? _buildAllMaterials() : _buildStudyBank(),
        ),
      ],
    );
  }

  // --- TAB 1: ALL MATERIALS ---
  Widget _buildAllMaterials() {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text("Popular This Week", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        SizedBox(height: 15),
        VaultCard(
          title: "PHY1004F Past Paper - Nov 2023",
          courseCode: "PHY1004F",
          subject: "Physics",
          author: "Luko",
          date: "Nov 6, 2025",
          rating: "4.9",
          downloads: "298",
        ),
        VaultCard(
          title: "MAM1000W Past Paper - June 2024",
          courseCode: "MAM1000W",
          subject: "Mathematics",
          author: "Thuhbest",
          date: "Nov 10, 2025",
          rating: "4.8",
          downloads: "234",
        ),
      ],
    );
  }

  // --- TAB 2: STUDY BANK (Renamed from Archive) ---
  Widget _buildStudyBank() {
    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ContributionStats(),
        const SizedBox(height: 25),
        const Text("Your Study Bank", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _bankItem(Icons.architecture, "Mathematics", "12 notes", Colors.blueAccent),
        _bankItem(Icons.science_outlined, "Physics", "8 notes", Colors.purpleAccent),
        _bankItem(Icons.laptop_mac, "Computer Science", "15 notes", Colors.tealAccent),
        const SizedBox(height: 20),
        const Center(child: Text("35 total notes stored", style: TextStyle(color: Colors.white38, fontSize: 12))),
      ],
    );
  }

  Widget _bankItem(IconData icon, String title, String count, Color accent) {
    return VaultActionButton(
      onTap: () => debugPrint("Opening $title"),
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
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(count, style: const TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return VaultActionButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C09E) : const Color(0xFF1E243A),
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

/// --- CLICK FEEDBACK WRAPPER (Applied to every button) ---
class VaultActionButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const VaultActionButton({super.key, required this.child, required this.onTap});

  @override
  State<VaultActionButton> createState() => _VaultActionButtonState();
}

class _VaultActionButtonState extends State<VaultActionButton> {
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