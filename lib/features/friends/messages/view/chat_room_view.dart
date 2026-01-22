import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/features/video_call/view/parallel_practice_view.dart';

class ChatRoomView extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final bool isGroup;

  const ChatRoomView({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.isGroup,
  });

  @override
  State<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<ChatRoomView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _markAsRead();
  }

  void _markAsRead() async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'unreadCounts.$currentUserId': 0,
    });
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String text = _messageController.text.trim();
    _messageController.clear();

    // 1. Add message document
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
      'senderId': currentUserId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
    });

    // 2. Identify receiver and update chat preview + unread count
    final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
    final List participants = chatDoc.data()?['participants'] ?? [];
    final String receiverId = participants.firstWhere((id) => id != currentUserId, orElse: () => '');

    final Map<String, dynamic> updates = {
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    };

    if (receiverId.isNotEmpty) {
      updates['unreadCounts.$receiverId'] = FieldValue.increment(1); // Increments receiver's badge
    }

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update(updates);

    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leadingWidth: 70,
        leading: Center(
          child: GestureDetector(
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
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatTitle, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            _buildPresenceLine(tealAccent),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined, color: Colors.white70),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ParallelPracticeView()),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: tealAccent));
                
                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    return _buildBubble(
                      data['text'] ?? '',
                      data['senderId'] == currentUserId,
                      data['status'] ?? 'sent',
                      data['timestamp'] as Timestamp?,
                    );
                  },
                );
              },
            ),
          ),
          _buildInputBar(cardColor, tealAccent),
        ],
      ),
    );
  }

  Widget _buildPresenceLine(Color tealAccent) {
    if (widget.isGroup) {
      return Text(
        "Group chat",
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, chatSnap) {
        final chatData = chatSnap.data?.data() as Map<String, dynamic>? ?? {};
        final participants = chatData['participants'] as List<dynamic>? ?? [];
        String? otherUserId;
        for (final participant in participants) {
          if (participant != currentUserId) {
            otherUserId = participant.toString();
            break;
          }
        }

        if (otherUserId == null) {
          return Text(
            "Last seen recently",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final Timestamp? lastSeen = userData['lastSeenAt'] as Timestamp? ?? userData['lastLoginAt'] as Timestamp?;
            bool isOnline = userData['isOnline'] == true;
            if (!isOnline && lastSeen != null) {
              final minutes = DateTime.now().difference(lastSeen.toDate()).inMinutes;
              if (minutes <= 2) {
                isOnline = true;
              }
            }

            final String label = isOnline ? "Online" : "Last seen ${_timeAgo(lastSeen)}";
            final Color labelColor = isOnline ? tealAccent : Colors.white.withValues(alpha: 0.4);

            return Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
              ],
            );
          },
        );
      },
    );
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return "recently";
    final now = DateTime.now();
    final diff = now.difference(timestamp.toDate());
    if (diff.inDays > 0) return "${diff.inDays}d ago";
    if (diff.inHours > 0) return "${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
    return "just now";
  }

  Widget _buildBubble(String text, bool isMe, String status, Timestamp? time) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    
    String formattedTime = "";
    if (time != null) {
      DateTime dt = time.toDate();
      formattedTime = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? tealAccent : cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? const Color(0xFF0F142B) : Colors.white.withValues(alpha: 0.9),
                fontSize: 15,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(
                    color: isMe ? Colors.black.withValues(alpha: 0.4) : Colors.white38,
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    status == 'read' ? Icons.done_all : Icons.done,
                    size: 14,
                    color: status == 'read' ? const Color(0xFF0F142B) : Colors.black.withValues(alpha: 0.3),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(Color cardColor, Color tealAccent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 25),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: TextStyle(color: Colors.white24),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Icon(Icons.attach_file_rounded, color: Colors.white.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: tealAccent,
              child: const Icon(Icons.send_rounded, color: Color(0xFF0F142B), size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
