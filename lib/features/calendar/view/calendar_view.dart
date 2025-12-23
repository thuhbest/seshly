import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart'; // Add this package
import '../widgets/calendar_grid.dart';
import '../widgets/event_card.dart';

class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  bool isMonthView = true;
  // Track the selected day (defaults to today/15th for your screenshot)
  int selectedDay = 15; 

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // --- Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Calendar", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text("October 2025", style: TextStyle(color: Colors.white54, fontSize: 16)),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() => isMonthView = !isMonthView),
                    child: Text(
                      isMonthView ? "List View" : "Month View",
                      style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // --- Month Selector ---
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(Icons.chevron_left, color: Colors.white),
                  Text("October 2025", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
              const SizedBox(height: 30),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isMonthView) ...[
                        // Pass selection logic to grid
                        CalendarGrid(
                          selectedDay: selectedDay,
                          onDaySelected: (day) => setState(() => selectedDay = day),
                        ),
                        const SizedBox(height: 30),
                        Text(
                          selectedDay == 15 ? "Today's Schedule" : "Schedule for Oct $selectedDay",
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Serif'),
                        ),
                        const SizedBox(height: 20),
                        // Conditional display based on selection
                        if (selectedDay == 15) ...[
                          const EventCard(title: "Calculus Midterm", time: "9:00 AM - 11:00 AM", location: "Room 301", type: "Exam", color: Colors.red),
                          const EventCard(title: "Physics Lab", time: "2:00 PM - 4:00 PM", location: "Science Building B", type: "Class", color: Colors.blue),
                        ] else
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text("No events scheduled for this day.", style: TextStyle(color: Colors.white38)),
                          ),
                      ] else ...[
                        const Text("Upcoming Events", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Serif')),
                        const SizedBox(height: 20),
                        const EventCard(title: "Calculus Midterm", tag: "Today", time: "9:00 AM - 11:00 AM", location: "Room 301", type: "Exam", color: Colors.red),
                        const EventCard(title: "Physics Lab", tag: "Today", time: "2:00 PM - 4:00 PM", location: "Science Building B", type: "Class", color: Colors.blue),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // --- Expandable FAB Menu (Speed Dial) ---
      // Only show if in Month View as requested
      floatingActionButton: isMonthView ? SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        backgroundColor: tealAccent,
        foregroundColor: backgroundColor,
        overlayColor: Colors.black,
        overlayOpacity: 0.5,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.event_note),
            label: 'Event',
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            onTap: () => debugPrint("Adding Event for day $selectedDay"),
          ),
          SpeedDialChild(
            child: const Icon(Icons.alarm_add),
            label: 'Reminder',
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            onTap: () => debugPrint("Adding Reminder"),
          ),
          SpeedDialChild(
            child: const Icon(Icons.qr_code_scanner),
            label: 'Scan',
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            onTap: () => debugPrint("Scanning Timetable"),
          ),
        ],
      ) : null,
    );
  }
}