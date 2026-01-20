import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:intl/intl.dart';
import '../data/calendar_repository.dart';
import '../models/calendar_event.dart';
import '../services/timetable_pdf_importer.dart';
import '../widgets/calendar_grid.dart';
import '../widgets/event_card.dart';

class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  bool isMonthView = true;

  late DateTime currentMonth;
  late int selectedDay;

  late final CalendarRepository _repo;
  late final TimetablePdfImporter _importer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    currentMonth = DateTime(now.year, now.month, 1);
    selectedDay = now.day;
    _repo = CalendarRepository();
    _importer = TimetablePdfImporter(_repo);
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);

    final monthLabel = DateFormat('MMMM yyyy').format(currentMonth);

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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Calendar",
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        monthLabel,
                        style: const TextStyle(color: Colors.white54, fontSize: 16),
                      ),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    splashRadius: 22,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        currentMonth = DateTime(currentMonth.year, currentMonth.month - 1, 1);
                        selectedDay = 1;
                      });
                    },
                  ),
                  Text(
                    monthLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    splashRadius: 22,
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
                        selectedDay = 1;
                      });
                    },
                  ),
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
                        StreamBuilder<List<CalendarEvent>>(
                          stream: _repo.streamEventsForMonth(currentMonth),
                          builder: (context, snap) {
                            final monthEvents = snap.data ?? const <CalendarEvent>[];

                            final indicators = <int, List<Color>>{};
                            for (final e in monthEvents) {
                              if (e.start.month != currentMonth.month || e.start.year != currentMonth.year) continue;
                              final day = e.start.day;
                              indicators.putIfAbsent(day, () => <Color>[]);
                              final c = Color(e.colorHex);
                              if (!indicators[day]!.contains(c) && indicators[day]!.length < 2) {
                                indicators[day]!.add(c);
                              }
                            }

                            return CalendarGrid(
                              selectedDay: selectedDay,
                              onDaySelected: (day) => setState(() => selectedDay = day),
                              month: currentMonth,
                              indicators: indicators,
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                        Text(
                          _scheduleTitleForSelection(currentMonth, selectedDay),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Serif',
                          ),
                        ),
                        const SizedBox(height: 20),

                        StreamBuilder<List<CalendarEvent>>(
                          stream: _repo.streamEventsForDay(DateTime(currentMonth.year, currentMonth.month, selectedDay)),
                          builder: (context, snap) {
                            final events = snap.data ?? const <CalendarEvent>[];

                            if (events.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text("No events scheduled for this day.", style: TextStyle(color: Colors.white38)),
                              );
                            }

                            return Column(
                              children: events
                                  .map((e) => EventCard(
                                        title: e.title,
                                        time: _formatTimeRange(e.start, e.end),
                                        location: e.location,
                                        type: e.type,
                                        color: Color(e.colorHex),
                                      ))
                                  .toList(),
                            );
                          },
                        ),
                      ] else ...[
                        Text(
                          _scheduleTitleForSelection(currentMonth, selectedDay),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Serif',
                          ),
                        ),
                        const SizedBox(height: 20),
                        StreamBuilder<List<CalendarEvent>>(
                          stream: _repo.streamEventsForDay(
                            DateTime(currentMonth.year, currentMonth.month, selectedDay),
                          ),
                          builder: (context, snap) {
                            final events = snap.data ?? const <CalendarEvent>[];

                            if (events.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text("No events scheduled for this day.", style: TextStyle(color: Colors.white38)),
                              );
                            }

                            return Column(
                              children: events
                                  .map((e) => EventCard(
                                        title: e.title,
                                        time: _formatTimeRange(e.start, e.end),
                                        location: e.location,
                                        type: e.type,
                                        color: Color(e.colorHex),
                                      ))
                                  .toList(),
                            );
                          },
                        ),
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
      // Removed Reminder, Added Seshly Themed Colors and Motion
      floatingActionButton: isMonthView
          ? SpeedDial(
              icon: Icons.add,
              activeIcon: Icons.close,
              spacing: 12,
              spaceBetweenChildren: 12,
              backgroundColor: tealAccent,
              foregroundColor: backgroundColor,
              overlayColor: Colors.black,
              overlayOpacity: 0.7,
              animationDuration: const Duration(milliseconds: 200),
              children: [
                SpeedDialChild(
                  child: const Icon(Icons.event_note, color: Colors.white),
                  backgroundColor: cardColor,
                  label: 'Event',
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  labelBackgroundColor: cardColor,
                  onTap: () async {
                    await _openAddEventDialog(
                      context,
                      defaultType: 'Class',
                    );
                  },
                ),
                SpeedDialChild(
                  child: const Icon(Icons.qr_code_scanner, color: Colors.white),
                  backgroundColor: cardColor,
                  label: 'Scan',
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  labelBackgroundColor: cardColor,
                  onTap: () async {
                    await _scanAndImportPdf();
                  },
                ),
              ],
            )
          : null,
    );
  }

  String _scheduleTitleForSelection(DateTime month, int day) {
    final selected = DateTime(month.year, month.month, day);
    final today = DateTime.now();
    final isToday = selected.year == today.year && selected.month == today.month && selected.day == today.day;
    if (isToday) return "Today's Schedule";
    return "Schedule for ${DateFormat('MMM d').format(selected)}";
  }

  String _formatTimeRange(DateTime start, DateTime end) {
    final fmt = DateFormat('h:mm a');
    return '${fmt.format(start)} - ${fmt.format(end)}';
  }

  String _relativeTag(DateTime start) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(start.year, start.month, start.day);
    final diff = d.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff > 1) return 'In $diff days';
    if (diff == -1) return 'Yesterday';
    return '${diff.abs()} days ago';
  }

  Future<void> _scanAndImportPdf() async {
    try {
      await _importer.importForMonth(currentMonth);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable imported.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to import timetable PDF.')),
      );
    }
  }

  Future<void> _openAddEventDialog(
    BuildContext context, {
    required String defaultType,
  }) async {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    final titleCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    String type = defaultType;
    final baseDate = DateTime(currentMonth.year, currentMonth.month, selectedDay);
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 11, minute: 0);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cardColor.withValues(alpha: 0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Add Event', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  children: [
                    _darkField(controller: titleCtrl, hint: 'Title (e.g. Calculus Midterm)'),
                    const SizedBox(height: 12),
                    _darkField(controller: locationCtrl, hint: 'Location (e.g. Room 301)'),
                    const SizedBox(height: 12),
                    _typeDropdown(
                      value: type,
                      onChanged: (v) => setDialogState(() => type = v),
                    ),
                    const SizedBox(height: 12),
                    _timeRow(
                      dialogContext: dialogContext,
                      label: 'Start',
                      time: startTime,
                      onPick: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          initialTime: startTime,
                          builder: (pickerContext, child) => Theme(
                            data: Theme.of(pickerContext).copyWith(
                              dialogBackgroundColor: backgroundColor,
                              colorScheme: const ColorScheme.dark(
                                primary: tealAccent,
                                surface: backgroundColor,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) setDialogState(() => startTime = picked);
                      },
                    ),
                    const SizedBox(height: 8),
                    _timeRow(
                      dialogContext: dialogContext,
                      label: 'End',
                      time: endTime,
                      onPick: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          initialTime: endTime,
                          builder: (pickerContext, child) => Theme(
                            data: Theme.of(pickerContext).copyWith(
                              dialogBackgroundColor: backgroundColor,
                              colorScheme: const ColorScheme.dark(
                                primary: tealAccent,
                                surface: backgroundColor,
                                onSurface: Colors.white,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (picked != null) setDialogState(() => endTime = picked);
                      },
                    ),
                  ],
                ),
              );
            }
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final location = locationCtrl.text.trim();

                if (title.isEmpty) return;

                final start = DateTime(
                  baseDate.year,
                  baseDate.month,
                  baseDate.day,
                  startTime.hour,
                  startTime.minute,
                );
                final end = DateTime(
                  baseDate.year,
                  baseDate.month,
                  baseDate.day,
                  endTime.hour,
                  endTime.minute,
                );

                final colorHex = EventTypePalette.colorHexForType(type);
                final id = DateTime.now().microsecondsSinceEpoch.toString();

                final event = CalendarEvent(
                  id: id,
                  title: title,
                  start: start,
                  end: end.isAfter(start) ? end : start.add(const Duration(hours: 1)),
                  location: location,
                  type: type,
                  colorHex: colorHex,
                  source: 'manual',
                  createdAt: DateTime.now(),
                );

                try {
                  await _repo.addEvent(event);
                } catch (_) {}

                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save', style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _darkField({required TextEditingController controller, required String hint}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF0F142B),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _typeDropdown({required String value, required void Function(String) onChanged}) {
    const types = <String>[
      'Tutoring',
      'Class',
      'Exam',
      'Deadline',
      'Assignment',
      'Meeting',
      'Study Group',
      'Reminder',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: types.contains(value) ? value : 'Class',
          dropdownColor: const Color(0xFF0F142B),
          iconEnabledColor: Colors.white70,
          style: const TextStyle(color: Colors.white),
          items: types
              .map((t) => DropdownMenuItem<String>(
                    value: t,
                    child: Text(t, style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _timeRow({
    required BuildContext dialogContext,
    required String label,
    required TimeOfDay time,
    required Future<void> Function() onPick,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () async => onPick(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F142B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(time.format(dialogContext), style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}
