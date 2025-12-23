import 'package:flutter/material.dart';
import '../widgets/message_tile.dart';

class MessagesView extends StatelessWidget {
  const MessagesView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

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
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Messages", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text("2 unread", style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                  Row(
                    children: [
                      // Back to Friends Button
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.group_outlined, color: Colors.white70, size: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Start New Conversation Button
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: tealAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: tealAccent, size: 22),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 25),

              // --- Search Bar ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const TextField(
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    icon: Icon(Icons.search, color: Colors.white54, size: 20),
                    hintText: "Search messages...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 25),

              // --- Message List ---
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    MessageTile(
                      title: "Study Group - Calculus",
                      subtitle: "Thuhbest: Thanks for the notes!",
                      time: "2m ago",
                      unreadCount: 3,
                      isGroup: true,
                      groupSize: 5,
                    ),
                    MessageTile(
                      title: "Tinswaole",
                      subtitle: "Your session is scheduled for tomorrow",
                      time: "15m ago",
                      isOnline: true,
                    ),
                    MessageTile(
                      title: "Physics Lab Partners",
                      subtitle: "Thimna: See you at 2pm",
                      time: "1h ago",
                      unreadCount: 1,
                      isGroup: true,
                      groupSize: 4,
                    ),
                    MessageTile(
                      title: "Faith",
                      subtitle: "The assignment is due Friday",
                      time: "3h ago",
                    ),
                    MessageTile(
                      title: "Chemistry Study Group",
                      subtitle: "Luko: Anyone have the lab results?",
                      time: "1d ago",
                      isGroup: true,
                      groupSize: 8,
                    ),
                    MessageTile(
                      title: "Prof. Johnson",
                      subtitle: "Office hours moved to 3pm",
                      time: "2d ago",
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}