import 'package:flutter/material.dart';

class CommentCard extends StatelessWidget {
  final String author, time, initials, text;
  final int likes;

  const CommentCard({super.key, required this.author, required this.time, required this.initials, required this.text, required this.likes});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            child: Text(initials, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(author, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(time, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Icon(Icons.favorite_border, color: Colors.white38, size: 16),
                      const SizedBox(width: 6),
                      Text(likes.toString(), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      const SizedBox(width: 20),
                      const Text("Reply", style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}