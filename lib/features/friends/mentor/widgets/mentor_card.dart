import 'package:flutter/material.dart';

class MentorCard extends StatelessWidget {
  final String name;
  final String year;
  final String major;
  final String badge;
  final String availability;
  final List<String> focusAreas;
  final VoidCallback? onMessage;
  final VoidCallback? onSchedule;

  const MentorCard({
    super.key,
    required this.name,
    required this.year,
    required this.major,
    this.badge = "Your Mentor",
    this.availability = "",
    this.focusAreas = const [],
    this.onMessage,
    this.onSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initialsForName(name);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0x1AFFFFFF),
                child: Text(initials, style: const TextStyle(color: Color(0xFF00C09E))),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        _mentorBadge(badge),
                      ],
                    ),
                    Text("$year - $major", style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          if (availability.isNotEmpty || focusAreas.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (availability.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFF00C09E), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      availability,
                      style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 12),
                    ),
                  ),
                ],
              ),
            if (focusAreas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: focusAreas
                    .map((area) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x1A00C09E),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(area, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 10)),
                        ))
                    .toList(),
              ),
            ],
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text("Message", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C09E),
                    foregroundColor: const Color(0xFF0F142B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onSchedule,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F142B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0x1AFFFFFF)),
                  ),
                  child: const Icon(Icons.calendar_today_outlined, color: Colors.white, size: 20),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _mentorBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1A00C09E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _initialsForName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'ME';
    final parts = trimmed.split(' ');
    final initials = parts
        .where((part) => part.isNotEmpty)
        .map((part) => part.characters.first)
        .take(2)
        .join()
        .toUpperCase();
    return initials.isEmpty ? 'ME' : initials;
  }
}
