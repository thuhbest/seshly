import 'package:flutter/material.dart';
import '../widgets/comment_card.dart';
import '../widgets/ai_tutor_help_view.dart';

class QuestionDetailView extends StatefulWidget {
  const QuestionDetailView({super.key});

  @override
  State<QuestionDetailView> createState() => _QuestionDetailViewState();
}

class _ScrollBehavior extends ScrollBehavior {
  // REMOVE @override annotation since buildViewportChrome doesn't exist in the parent class
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) => child;
}

class _QuestionDetailViewState extends State<QuestionDetailView> {
  bool isAiView = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Question", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          _headerCircleButton(Icons.share_outlined),
          _headerCircleButton(Icons.more_horiz),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: _ScrollBehavior(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Question Header ---
                    Row(
                      children: [
                        _avatar("TM"),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Thimna", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("5m ago", style: TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        _tag("Mathematics"),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "How do I solve quadratic equations using the quadratic formula?",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "I understand the basic concept, but I'm struggling with applying the formula to complex equations. Can someone provide a step-by-step breakdown?",
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    const Row(
                      children: [
                        Icon(Icons.favorite_border, color: Colors.white38, size: 18),
                        SizedBox(width: 6),
                        Text("24", style: TextStyle(color: Colors.white38)),
                        SizedBox(width: 20),
                        Icon(Icons.chat_bubble_outline, color: Colors.white38, size: 18),
                        SizedBox(width: 6),
                        Text("3", style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                    const Divider(color: Colors.white10, height: 40),

                    // --- Tab Toggle ---
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cardColor.withValues(alpha: 128), // 0.5 * 255 = 128
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _tabButton("Comments (3)", !isAiView, () => setState(() => isAiView = false)),
                          _tabButton("Ask Sesh", isAiView, () => setState(() => isAiView = true), icon: Icons.auto_awesome),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // --- Dynamic Body ---
                    isAiView ? const AiTutorHelpView() : _buildCommentsList(),
                  ],
                ),
              ),
            ),
          ),
          
          // --- Comment Input (Hidden in AI View) ---
          if (!isAiView) _buildCommentInput(),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    return const Column(
      children: [
        CommentCard(
          author: "Thuhbest",
          time: "3m ago",
          initials: "T",
          text: "The quadratic formula is: x = (-b ± √(b²-4ac)) / 2a. First, identify your a, b, and c values from the equation ax² + bx + c = 0.",
          likes: 18,
        ),
        CommentCard(
          author: "Faith",
          time: "8m ago",
          initials: "F",
          text: "I found it helpful to memorize the formula by singing it! Also, make sure to check if the discriminant (b²-4ac) is positive before solving.",
          likes: 12,
        ),
        CommentCard(
          author: "Tinswaole",
          time: "10m ago",
          initials: "T",
          text: "Pro tip: Always simplify your answer and check by plugging it back into the original equation!",
          likes: 9,
        ),
      ],
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 13))), // 0.05 * 255 = 13
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Add a comment...",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 13), // 0.05 * 255 = 13
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const CircleAvatar(
            backgroundColor: Color(0xFF00C09E),
            child: Icon(Icons.send, color: Color(0xFF0F142B), size: 20),
          ),
        ],
      ),
    );
  }

  // --- UI Helpers ---
  Widget _headerCircleButton(IconData icon) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 13), shape: BoxShape.circle), // 0.05 * 255 = 13
      child: IconButton(icon: Icon(icon, color: const Color(0xFF00C09E), size: 20), onPressed: () {}),
    );
  }

  Widget _avatar(String text) {
    return CircleAvatar(
      backgroundColor: const Color(0xFF00C09E).withValues(alpha: 25), // 0.1 * 255 = 25
      child: Text(text, style: const TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold)),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 13), borderRadius: BorderRadius.circular(20)), // 0.05 * 255 = 13
      child: Text(label, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _tabButton(String label, bool isSelected, VoidCallback onTap, {IconData? icon}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E243A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 25)) : null, // 0.1 * 255 = 25
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, color: isSelected ? const Color(0xFF00C09E) : Colors.white38, size: 16), const SizedBox(width: 8)],
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}