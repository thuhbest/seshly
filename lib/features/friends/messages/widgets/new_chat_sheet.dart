import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../view/chat_room_view.dart';

class NewChatSheet extends StatefulWidget {
  const NewChatSheet({super.key});

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _unfriend(String friendId, String friendName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E243A),
        title: const Text("Unfriend", style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to unfriend $friendName?", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Unfriend", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').doc(friendId));
      batch.delete(FirebaseFirestore.instance.collection('users').doc(friendId).collection('friends').doc(currentUserId));
      await batch.commit();
    }
  }

  void _navigateToChat(String friendId, String friendName) {
    Navigator.pop(context); // Close the bottom sheet first
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatRoomView(
          chatId: friendId, // You might want to generate a proper chat ID
          chatTitle: friendName,
          isGroup: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF161B30);
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("New Conversation", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () { /* Add Create Group Logic */ },
                icon: const Icon(Icons.groups, color: tealAccent),
                label: const Text("Create Group", style: TextStyle(color: tealAccent)),
              )
            ],
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final friends = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friendId = friends[index].id;
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(friendId).get(),
                      builder: (context, fSnap) {
                        if (!fSnap.hasData) return const SizedBox.shrink();
                        final data = fSnap.data!.data() as Map<String, dynamic>;
                        final friendName = data['fullName'];
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: tealAccent, child: Text(friendName[0], style: const TextStyle(color: Colors.white))),
                          title: Text(friendName, style: const TextStyle(color: Colors.white)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chat_bubble_outline, color: tealAccent),
                                onPressed: () => _navigateToChat(friendId, friendName),
                              ),
                              IconButton(
                                icon: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                                onPressed: () => _unfriend(friendId, friendName),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}