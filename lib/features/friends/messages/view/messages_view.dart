import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/message_tile.dart';
import 'chat_room_view.dart';
import '../widgets/new_chat_sheet.dart';

class MessagesView extends StatelessWidget {
  const MessagesView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

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
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Messages", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                          Text("Direct & Groups", style: TextStyle(color: Colors.white54, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const NewChatSheet(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tealAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: tealAccent, size: 22),
                    ),
                  ),
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
              // --- Chat List Section ---
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .where('participants', arrayContains: currentUserId)
                      .orderBy('lastMessageTime', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      debugPrint("Firestore Error: ${snapshot.error}");
                      return Center(child: Text("Error loading chats", style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.5))));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: tealAccent));
                    }

                    final chats = snapshot.data?.docs ?? [];

                    // --- Empty State ---
                    if (chats.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, 
                              size: 70, color: Colors.white.withValues(alpha: 0.05)),
                            const SizedBox(height: 20),
                            const Text(
                              "No conversations yet",
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Click the + button above to message\na friend or create a study group.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    // --- List of Real Chats ---
                    return ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chatData = chats[index].data() as Map<String, dynamic>;
                        final chatId = chats[index].id;
                        final isGroup = chatData['isGroup'] ?? false;
                        
                        // Extract participant name that isn't the current user
                        String chatName = isGroup ? (chatData['groupName'] ?? "Group") : "Seshly User";
                        if (!isGroup && chatData['participantNames'] != null) {
                          final namesMap = chatData['participantNames'] as Map<String, dynamic>;
                          namesMap.forEach((uid, name) {
                            if (uid != currentUserId) chatName = name;
                          });
                        }

                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatRoomView(
                                chatId: chatId,
                                chatTitle: chatName,
                                isGroup: isGroup,
                              ),
                            ),
                          ),
                          child: MessageTile(
                            title: chatName,
                            subtitle: chatData['lastMessage'] ?? "Tap to chat",
                            time: _getTimeString(chatData['lastMessageTime'] as Timestamp?),
                            isGroup: isGroup,
                            unreadCount: 0,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeString(Timestamp? timestamp) {
    if (timestamp == null) return "";
    DateTime date = timestamp.toDate();
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}