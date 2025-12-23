// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import '../friend/widgets/friend_card.dart';
import '../mentor/widgets/mentor_card.dart';
import '../mentor/widgets/goals_card.dart';
// 1. Import the MessagesView
import '../messages/view/messages_view.dart';

class FriendsView extends StatefulWidget {
  const FriendsView({super.key});

  @override
  State<FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<FriendsView> {
  bool isMentorshipTab = false;

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Friends", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text("Connect with your study community", style: TextStyle(color: Colors.white54)),
                  ],
                ),
                Row(
                  children: [
                    _headerBadgeIcon(Icons.person_add_outlined, "2"),
                    // 2. Wrap the chat icon helper with navigation logic
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MessagesView()),
                      ),
                      child: _headerBadgeIcon(Icons.chat_bubble_outline, "3"),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(15)),
              child: const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  icon: Icon(Icons.search, color: Colors.white54),
                  hintText: "Search by name, student number, or email",
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Try searching: "Thuhbest", "LUKLUK005", or "faith@myuct.ac.za"',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.5), 
                borderRadius: BorderRadius.circular(12)
              ),
              child: Row(
                children: [
                  _toggleButton("Friends", "4", !isMentorshipTab, () => setState(() => isMentorshipTab = false)),
                  _toggleButton("Mentorship", null, isMentorshipTab, () => setState(() => isMentorshipTab = true)),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: isMentorshipTab ? _buildMentorshipTab() : _buildFriendsTab(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton(String label, String? count, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E243A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 0.1)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold)),
              if (count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C09E).withValues(alpha: 0.2), 
                    borderRadius: BorderRadius.circular(5)
                  ),
                  child: Text(count, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 10, fontWeight: FontWeight.bold)),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerBadgeIcon(IconData icon, String count) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF00C09E), size: 22),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Color(0xFF00C09E), shape: BoxShape.circle),
            child: Text(count, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  Widget _buildFriendsTab() {
    return const Column(
      children: [
        FriendCard(name: "Thimna", id: "THHBES002", year: "3rd Year", streak: "12", mins: "350"),
        FriendCard(name: "Faith", id: "FAIFAI004", year: "1st Year", streak: "5", mins: "480"),
      ],
    );
  }

  Widget _buildMentorshipTab() {
    return Column(
      children: [
        _buildMoodSelector(),
        const SizedBox(height: 20),
        const MentorCard(name: "Thimna", year: "3rd Year", major: "Computer Science"),
        const SizedBox(height: 20),
        const GoalsCard(),
      ],
    );
  }

  Widget _buildMoodSelector() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF00C09E).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF00C09E).withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_border, color: Color(0xFF00C09E), size: 18),
              SizedBox(width: 8),
              Text("How are you feeling this week?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _moodItem(Icons.sentiment_very_dissatisfied, "Struggling", Colors.redAccent),
              _moodItem(Icons.sentiment_neutral, "Okay", Colors.white54),
              _moodItem(Icons.sentiment_very_satisfied, "Good", const Color(0xFF00C09E)),
            ],
          )
        ],
      ),
    );
  }

  Widget _moodItem(IconData icon, String label, Color color) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF1E243A), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}