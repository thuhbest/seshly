import 'package:flutter/material.dart';

class SeshTabBar extends StatelessWidget {
  final String selectedTab;
  final Function(String) onTabChanged;

  const SeshTabBar({super.key, required this.selectedTab, required this.onTabChanged});

  final List<String> tabs = const ["AI Assist", "Vault", "Archive", "Progress"];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5), // Using withValues()
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: tabs.map((tab) {
          bool isSelected = selectedTab == tab;
          return GestureDetector(
            onTap: () => onTabChanged(tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E243A) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 0.1)) : null, // Using withValues()
              ),
              child: Text(
                tab,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.54), // Using withValues()
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}