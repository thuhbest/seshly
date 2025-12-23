// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';

class CalendarGrid extends StatelessWidget {
  final int selectedDay;
  final Function(int) onDaySelected;

  const CalendarGrid({
    super.key, 
    required this.selectedDay, 
    required this.onDaySelected
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final List<String> weekDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekDays.map((day) => Text(day, style: const TextStyle(color: Colors.white54, fontSize: 12))).toList(),
        ),
        const SizedBox(height: 15),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 35,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            int day = index - 2; 
            if (day < 1 || day > 31) return const SizedBox();

            bool isSelected = day == selectedDay; // Highlight selected day
            bool hasExam = day == 15;
            bool hasClass = day == 15 || day == 18;

            return GestureDetector(
              onTap: () => onDaySelected(day), // Update state on tap
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
                  // Border changes based on selection
                  border: Border.all(
                    color: isSelected ? tealAccent : Colors.white.withValues(alpha: 0.05), 
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      day.toString(),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (day == 15) ...[
                      _indicator(Colors.red),
                      _indicator(Colors.blue),
                    ] else if (day == 18)
                      _indicator(Colors.blue),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _indicator(Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      width: 15,
      height: 2,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
    );
  }
}