import 'package:flutter/material.dart';

class MentorCard extends StatelessWidget {
  final String name, year, major;

  const MentorCard({super.key, required this.name, required this.year, required this.major});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A), // Equivalent to Color(0xFF1E243A).withOpacity(0.5)
        borderRadius: BorderRadius.circular(15)
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30, 
                backgroundColor: const Color(0x1AFFFFFF), // Equivalent to Colors.white.withOpacity(0.1)
                child: Text(
                  name.substring(0, 2).toUpperCase(), 
                  style: const TextStyle(color: Color(0xFF00C09E))
                )
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
                        _mentorBadge(),
                      ],
                    ),
                    Text("$year • $major", style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 13)), // Equivalent to Colors.white54
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text("Message", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C09E), 
                    foregroundColor: const Color(0xFF0F142B), 
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(12), 
                decoration: BoxDecoration(
                  color: const Color(0xFF0F142B), 
                  borderRadius: BorderRadius.circular(10), 
                  border: Border.all(color: const Color(0x1AFFFFFF)) // Equivalent to Colors.white10
                ), 
                child: const Icon(Icons.calendar_today_outlined, color: Colors.white, size: 20)
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _mentorBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
      decoration: BoxDecoration(
        color: const Color(0x1A00C09E), // Equivalent to Color(0xFF00C09E).withOpacity(0.1)
        borderRadius: BorderRadius.circular(10)
      ), 
      child: const Text(
        "Your Mentor", 
        style: TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold)
      )
    );
  }
}