import 'package:flutter/material.dart';
import '../view/question_detail_view.dart'; // Import QuestionDetailView

class PostCard extends StatelessWidget {
  final String subject;
  final String time;
  final String question;
  final String author;
  final int likes;
  final int comments;

  const PostCard({
    super.key,
    required this.subject,
    required this.time,
    required this.question,
    required this.author,
    required this.likes,
    required this.comments,
  });

  @override
  Widget build(BuildContext context) {
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF), // Equivalent to Colors.white.withOpacity(0.05)
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(subject, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Text(time, style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 12)), // Equivalent to Colors.white54
            ],
          ),
          const SizedBox(height: 15),
          Text(
            question,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text("by $author", style: const TextStyle(color: Color(0x88FFFFFF))), // Equivalent to Colors.white54
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _actionIcon(Icons.thumb_up_alt_outlined, likes.toString()),
              // Comment row wrapped in GestureDetector
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const QuestionDetailView()),
                  );
                },
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0x88FFFFFF)), // Equivalent to Colors.white54
                    const SizedBox(width: 4),
                    Text(comments.toString(), style: const TextStyle(color: Color(0x88FFFFFF))), // Equivalent to Colors.white54
                  ],
                ),
              ),
              _actionIcon(Icons.person_add_alt_1_outlined, "Tutor", color: tealAccent),
              const Icon(Icons.repeat, color: Color(0x88FFFFFF), size: 20), // Equivalent to Colors.white54
            ],
          )
        ],
      ),
    );
  }

  Widget _actionIcon(IconData icon, String label, {Color color = const Color(0x88FFFFFF)}) { // Equivalent to Colors.white54
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}