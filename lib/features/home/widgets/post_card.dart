import 'package:flutter/material.dart';
import '../view/question_detail_view.dart'; // Import QuestionDetailView
import 'package:seshly/features/tutors/view/find_tutor_view.dart'; // Import FindTutorView

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
              // Like button with pressing effect
              ActionIconButton(
                icon: Icons.thumb_up_alt_outlined,
                label: likes.toString(),
                onTap: () {
                  // Handle like action
                  print('Liked the post');
                },
              ),
              // Comment button with pressing effect
              ActionIconButton(
                icon: Icons.chat_bubble_outline,
                label: comments.toString(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const QuestionDetailView()),
                  );
                },
              ),
              // Find Tutor button with pressing effect - Updated to navigate to FindTutorView
              ActionIconButton(
                icon: Icons.person_add_alt_1_outlined,
                label: "Tutor",
                color: tealAccent,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const FindTutorView()));
                },
              ),
              // Share button with pressing effect
              ActionIconButton(
                icon: Icons.repeat,
                label: "",
                onTap: () {
                  // Handle share action
                  print('Share tapped');
                },
              ),
            ],
          )
        ],
      ),
    );
  }
}

/// A dedicated button for post actions with pressing effect
class ActionIconButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ActionIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.color = const Color(0x88FFFFFF), // Default to Colors.white54 equivalent
    required this.onTap,
  });

  @override
  State<ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<ActionIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // Animation scale: 1.0 is normal, 0.9 is shrunk
    final double scale = _isPressed ? 0.9 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Row(
          children: [
            Icon(widget.icon, color: widget.color, size: 20),
            if (widget.label.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(widget.label, style: TextStyle(color: widget.color)),
            ]
          ],
        ),
      ),
    );
  }
}