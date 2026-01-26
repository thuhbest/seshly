import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class MarketCategoryBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelected;
  final List<String> categories;

  const MarketCategoryBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.categories = const ["All Items", "Notes", "Tech", "Bags", "Stationery", "Other"],
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((cat) {
          final bool isSelected = selected == cat;
          return PressableScale(
            onTap: () => onSelected(cat),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00C09E) : const Color(0xFF1E243A).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0F142B) : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
                child: Text(cat),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
