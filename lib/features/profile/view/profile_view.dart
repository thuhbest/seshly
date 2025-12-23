import 'package:flutter/material.dart';

import '../widgets/stats_grid.dart';
import '../widgets/achievement_card.dart';
import 'settings_view.dart'; // Since SettingsView is in the same folder: lib/features/profile/view/

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header Section ---
            Container(
              padding: const EdgeInsets.only(top: 60, left: 25, right: 25, bottom: 30),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF163E44).withValues(alpha: 0.8),
                    backgroundColor,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: tealAccent.withValues(alpha: 0.1),
                            child: const Text("TH", 
                              style: TextStyle(color: tealAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 20),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Thuhbest", 
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                              Text("thuhbest@myuct.ac.za", 
                                style: TextStyle(color: Colors.white54, fontSize: 14)),
                              SizedBox(height: 8),
                              _UniversityBadge(label: "University of Cape Town"),
                            ],
                          ),
                        ],
                      ),
                      _SettingsButton(),
                    ],
                  ),
                  const SizedBox(height: 30),
                  // --- Level Progress ---
                  const _LevelProgressBar(level: 5, currentXP: 342, totalXP: 500),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StatsGrid(),
                  const SizedBox(height: 30),
                  const Text("Achievements", 
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Serif')),
                  const SizedBox(height: 20),
                  // --- Achievements List ---
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 15,
                    crossAxisSpacing: 15,
                    childAspectRatio: 1.1,
                    children: const [
                      AchievementCard(
                        icon: Icons.military_tech_outlined,
                        title: "Fast Learner",
                        desc: "Complete 10 study sessions",
                      ),
                      AchievementCard(
                        icon: Icons.military_tech_outlined,
                        title: "Helpful Student",
                        desc: "50+ helpful answers",
                      ),
                    ],
                  ),
                  const SizedBox(height: 100), // Bottom padding
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UniversityBadge extends StatelessWidget {
  final String label;
  const _UniversityBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00C09E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, 
        style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: IconButton(
        icon: const Icon(Icons.settings_outlined, color: Colors.white70),
        onPressed: () {
          // Navigate to SettingsView instead of signing out
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsView()),
          );
        },
      ),
    );
  }
}

class _LevelProgressBar extends StatelessWidget {
  final int level, currentXP, totalXP;
  const _LevelProgressBar({required this.level, required this.currentXP, required this.totalXP});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Level $level - Advanced Learner", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text("$currentXP/$totalXP XP", 
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: currentXP / totalXP,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            color: const Color(0xFF00C09E),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}