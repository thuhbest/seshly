import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CalendarGrid extends StatelessWidget {
  final int selectedDay;
  final Function(int) onDaySelected;

  // Backend-driven:
  final DateTime month; // first day of month
  final Map<int, List<Color>> indicators; // day -> colors (max 2)

  const CalendarGrid({
    super.key,
    required this.selectedDay,
    required this.onDaySelected,
    required this.month,
    required this.indicators,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final List<String> weekDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Convert to Sunday-based index for grid (Sun=0..Sat=6)
    final firstWeekdaySundayBased = (firstDay.weekday % 7); // Mon=1..Sun=7 -> Sun=0
    // Your old layout had an offset; this replaces it correctly.
    final leadingEmpty = firstWeekdaySundayBased;

    // Fixed 35 cells like your UI. (Some months need 42, but your design uses 35)
    const totalCells = 35;

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
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final day = index - leadingEmpty + 1;
            if (day < 1 || day > daysInMonth) return const SizedBox();

            final isSelected = day == selectedDay;
            final colors = indicators[day] ?? const <Color>[];

            return GestureDetector(
              onTap: () => onDaySelected(day),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(10),
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
                    for (final c in colors) _indicator(c),
                  ],
                ),
              ),
            );
          },
        ),
        // (No visible UI change; this is just a safeguard if month doesn't fit 35 cells.)
        if (_needsSixWeeks(firstDay, daysInMonth))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              DateFormat('MMMM').format(month),
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
            ),
          ),
      ],
    );
  }

  bool _needsSixWeeks(DateTime firstDay, int daysInMonth) {
    final leading = (firstDay.weekday % 7);
    return (leading + daysInMonth) > 35;
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
