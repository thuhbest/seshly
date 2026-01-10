import 'package:flutter/material.dart';

class FriendCard extends StatelessWidget {
  final String name, id, year, streak, mins;
  final VoidCallback onMessage; 

  const FriendCard({
    super.key,
    required this.name,
    required this.id,
    required this.year,
    required this.streak,
    required this.mins,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    const Color scaffoldBg = Color(0xFF0F142B);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    child: Text(
                      name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                      style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: tealAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: scaffoldBg, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        _statusBadge("Online"),
                      ],
                    ),
                    Text("$id • $year", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _iconText(Icons.local_fire_department, "$streak day streak"),
                        const SizedBox(width: 15),
                        _iconText(Icons.timer_outlined, "$mins Sesh Mins"),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              // Message Button - Now full width
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onMessage, 
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text("Message", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scaffoldBg,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10), 
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.05))
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _statusBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF00C09E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFF00C09E), fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _iconText(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}