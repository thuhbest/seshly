import 'package:flutter/material.dart';
import 'vault_card.dart';
import 'contribution_stats.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Upload Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Study Vault", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text("Community-shared study materials verified by\nSesh", 
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: const Text("Upload"),
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: const Color(0xFF0F142B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            )
          ],
        ),
        const SizedBox(height: 20),

        // Toggle Buttons
        Row(
          children: [
            _toggleBtn("All Materials", isAllMaterials, () => setState(() => isAllMaterials = true)),
            const SizedBox(width: 12),
            _toggleBtn("My Uploads (3)", !isAllMaterials, () => setState(() => isAllMaterials = false)),
          ],
        ),
        const SizedBox(height: 25),

        // Dynamic Content based on toggle
        if (isAllMaterials) ...[
          const Text("Popular This Week", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          const VaultCard(
            title: "PHY1004F Past Paper - Nov 2023",
            courseCode: "PHY1004F",
            subject: "Physics",
            author: "Luko",
            date: "Nov 6, 2025",
            rating: "4.9",
            downloads: "298",
          ),
          const VaultCard(
            title: "MAM1000W Past Paper - June 2024",
            courseCode: "MAM1000W",
            subject: "Mathematics",
            author: "Thuhbest",
            date: "Nov 10, 2025",
            rating: "4.8",
            downloads: "234",
          ),
        ] else ...[
          const ContributionStats(),
          const SizedBox(height: 20),
          _buildSearchAndFilters(),
          const SizedBox(height: 20),
          const Text("3 materials found", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 15),
          const VaultCard(
            title: "MAM1000W Past Paper - June 2024",
            courseCode: "MAM1000W",
            subject: "Mathematics",
            author: "Thuhbest",
            date: "Nov 10, 2025",
            rating: "4.8",
            downloads: "234",
          ),
        ],
      ],
    );
  }

  Widget _toggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C09E) : const Color(0xFF1E243A),
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? null : Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            if (!isSelected && label.contains("My")) 
              const Icon(Icons.person_outline, color: Colors.white70, size: 18),
            if (!isSelected && label.contains("My")) const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(color: const Color(0xFF1E243A), borderRadius: BorderRadius.circular(10)),
          child: const TextField(
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              icon: Icon(Icons.search, color: Colors.white54),
              hintText: "Search by title, subject, or course code...",
              hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _filterDropdown("All Subjects"),
            const SizedBox(width: 10),
            _filterDropdown("All Types"),
          ],
        ),
        const SizedBox(height: 10),
        _filterDropdown("All Year Levels", fullWidth: true),
      ],
    );
  }

  Widget _filterDropdown(String label, {bool fullWidth = false}) {
    return Expanded(
      flex: fullWidth ? 1 : 0,
      child: Container(
        width: fullWidth ? double.infinity : 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E243A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
            const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}