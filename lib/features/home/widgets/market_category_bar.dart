import 'package:flutter/material.dart';

class MarketCategoryBar extends StatefulWidget {
  const MarketCategoryBar({super.key});

  @override
  State<MarketCategoryBar> createState() => _MarketCategoryBarState();
}

class _MarketCategoryBarState extends State<MarketCategoryBar> {
  String selected = "All Items";
  final List<String> categories = ["All Items", "Notes", "Tech", "Bags", "Stationery"];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((cat) {
          bool isSelected = selected == cat;
          return GestureDetector(
            onTap: () => setState(() => selected = cat),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00C09E) : const Color(0xFF1E243A).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0F142B) : Colors.white70,
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