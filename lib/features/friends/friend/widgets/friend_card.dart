import 'package:flutter/material.dart';

class FriendCard extends StatelessWidget {
  final String name, id, year, streak, mins;

  const FriendCard({super.key, required this.name, required this.id, required this.year, required this.streak, required this.mins});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5), 
        borderRadius: BorderRadius.circular(15)
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
                    child: Text(name.substring(0, 2).toUpperCase(), style: const TextStyle(color: Color(0xFF00C09E)))
                  ),
                  Positioned(
                    right: 0, 
                    bottom: 0, 
                    child: Container(
                      width: 12, height: 12, 
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C09E), 
                        shape: BoxShape.circle, 
                        border: Border.all(color: const Color(0xFF0F142B), width: 2)
                      )
                    )
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
                        Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        _statusBadge("Online"),
                      ],
                    ),
                    Text("$id • $year", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _iconText(Icons.trending_up, "$streak day streak"),
                        const SizedBox(width: 15),
                        _iconText(Icons.circle, "$mins Sesh Minutes", size: 6),
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
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text("Message", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F142B), 
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
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
        color: Colors.green.withValues(alpha: 0.1), 
        borderRadius: BorderRadius.circular(5)
      ), 
      child: Text(text, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 10, fontWeight: FontWeight.bold))
    );
  }

  Widget _iconText(IconData icon, String text, {double size = 16}) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: size), 
        const SizedBox(width: 5), 
        Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11))
      ]
    );
  }
}