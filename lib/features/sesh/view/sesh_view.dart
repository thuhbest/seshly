import 'package:flutter/material.dart';
import '../widgets/sesh_tab_bar.dart';
import '../widgets/sesh_feature_card.dart';
import '../widgets/sesh_input_box.dart';
import '../widgets/vault_view.dart'; 

class SeshView extends StatefulWidget {
  const SeshView({super.key});

  @override
  State<SeshView> createState() => _SeshViewState();
}

class _SeshViewState extends State<SeshView> {
  String _selectedTab = "AI Assist";

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Sesh AI", 
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                    ),
                    Text(
                      "Your personal study assistant", 
                      style: TextStyle(color: Colors.white54)
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.05 * 255).round()), // fixed withOpacity
                    shape: BoxShape.circle
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFF00C09E), size: 24),
                ),
              ],
            ),
            const SizedBox(height: 25),
            SeshTabBar(
              selectedTab: _selectedTab,
              onTabChanged: (tab) => setState(() => _selectedTab = tab),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _selectedTab == "Vault" 
                  ? const VaultView()
                  : Column(
                      children: [
                        const SeshFeatureCard(
                          title: "Snap & Study",
                          description: "Take photos of diagrams and get AI explanations",
                          buttonText: "Take Photo",
                          icon: Icons.camera_alt_outlined,
                        ),
                        const SeshFeatureCard(
                          title: "Smart Notes",
                          description: "Convert your notes into organized study guides",
                          buttonText: "Create Notes",
                          icon: Icons.description_outlined,
                        ),
                        const SeshFeatureCard(
                          title: "Practice Quiz",
                          description: "Generate custom quizzes from your study material",
                          buttonText: "Start Quiz",
                          icon: Icons.track_changes_outlined,
                        ),
                        const SizedBox(height: 20),
                        const SeshInputBox(),
                        const SizedBox(height: 40),
                      ],
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
