import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class CategorySelector extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const CategorySelector({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final List<String> categories = const [
    "All", "Mathematics", "Physics", "Chemistry", "Biology", "Computer Science", "Engineering"
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((category) {
          bool isSelected = selectedCategory == category;
          return PressableScale(
            onTap: () => onCategorySelected(category),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00C09E) : const Color(0xFF1E243A),
                borderRadius: BorderRadius.circular(20),
                border: isSelected ? null : Border.all(color: Colors.white10),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0F142B) : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
                child: Text(category),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
