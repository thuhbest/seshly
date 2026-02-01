import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:seshly/features/sesh/view/sesh_ai_chat_view.dart';

class SeshAiThreadsView extends StatelessWidget {
  const SeshAiThreadsView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0F142B);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Text('Please sign in to see your chats.', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final threads = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_threads')
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Sesh AI Chats', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: threads,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
          }
          if (snap.hasError) {
            return const Center(child: Text('Failed to load chats.', style: TextStyle(color: Colors.white54)));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No chats yet.', style: TextStyle(color: Colors.white38)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final title = (data['title'] ?? 'Sesh AI').toString();
              final lastMessage = (data['lastMessage'] ?? '').toString();
              final threadId = docs[index].id;
              return ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: const Color(0xFF1E243A),
                title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  lastMessage.isEmpty ? 'Tap to open chat' : lastMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SeshAiChatView(
                        title: title,
                        threadId: threadId,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
