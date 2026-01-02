import 'package:flutter/material.dart';
import '../widgets/progress_stat_card.dart';

class ProgressView extends StatelessWidget {
  const ProgressView({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Study Progress",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Track your learning journey",
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 30),

          // --- Stats Grid ---
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 15,
            crossAxisSpacing: 15,
            childAspectRatio: 1.1,
            children: [
              ProgressStatCard(
                icon: Icons.timer_outlined,
                value: "24.5",
                label: "Study Hours",
                accentColor: Colors.purpleAccent,
                onTap: () => debugPrint("Study Hours clicked"),
              ),
              ProgressStatCard(
                icon: Icons.note_alt_outlined,
                value: "35",
                label: "Notes Created",
                accentColor: Colors.orangeAccent,
                onTap: () => debugPrint("Notes Created clicked"),
              ),
              ProgressStatCard(
                icon: Icons.check_circle_outline,
                value: "156",
                label: "Problems Solved",
                accentColor: Colors.blueAccent,
                onTap: () => debugPrint("Problems Solved clicked"),
              ),
              ProgressStatCard(
                icon: Icons.track_changes_outlined,
                value: "12",
                label: "Goals Completed",
                accentColor: Colors.pinkAccent,
                onTap: () => debugPrint("Goals Completed clicked"),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}