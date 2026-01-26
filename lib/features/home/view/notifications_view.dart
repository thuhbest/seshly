import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/features/friends/messages/view/chat_room_view.dart';
import 'package:seshly/features/friends/widgets/friend_requests_dialog.dart';
import '../widgets/notification_tile.dart';
import 'question_detail_view.dart';
import 'market_item_detail_view.dart';
import 'market_order_detail_view.dart';
import 'package:seshly/widgets/responsive.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  static const Color _backgroundColor = Color(0xFF0F142B);
  static const Color _tealAccent = Color(0xFF00C09E);

  Future<void> _markAllRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final notificationsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications');

    const int batchLimit = 450;
    bool hasMore = true;

    while (hasMore) {
      final snapshot = await notificationsRef
          .where('isRead', isEqualTo: false)
          .limit(batchLimit)
          .get();

      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All notifications marked as read")),
      );
    }
  }

  Future<void> _markReadIfNeeded(DocumentReference ref, bool isRead) async {
    if (isRead) return;
    await ref.update({'isRead': true});
  }

  Future<void> _handleNotificationTap(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final bool isRead = data['isRead'] == true;
    await _markReadIfNeeded(doc.reference, isRead);
    if (!mounted) return;

    final String? type = data['type'] as String?;
    final String? postId = data['postId'] as String?;
    final String? chatId = data['chatId'] as String?;
    final String? actorName = data['actorName'] as String?;
    final String? itemId = data['itemId'] as String?;
    final String? orderId = data['orderId'] as String?;

    switch (type) {
      case 'comment':
      case 'helpful':
        if (postId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QuestionDetailView(postId: postId),
            ),
          );
        }
        break;
      case 'message':
        if (chatId != null) {
          await _openChatFromNotification(chatId, actorName);
        }
        break;
      case 'friend_request':
        showDialog(
          context: context,
          builder: (_) => const FriendRequestsDialog(),
        );
        break;
      case 'market_order':
        if (orderId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MarketOrderDetailView(orderId: orderId),
            ),
          );
        } else if (itemId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MarketItemDetailView(itemId: itemId),
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  Future<void> _openChatFromNotification(
    String chatId,
    String? fallbackName,
  ) async {
    final chatSnap = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .get();
    if (!chatSnap.exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat not found")),
      );
      return;
    }

    final chatData = chatSnap.data() ?? <String, dynamic>{};
    final bool isGroup = chatData['isGroup'] == true;
    String chatTitle = fallbackName ?? "Chat";

    if (isGroup) {
      final String? title = chatData['title'] as String?;
      if (title != null && title.trim().isNotEmpty) {
        chatTitle = title;
      }
    } else {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final Map<String, dynamic>? participantNames =
          chatData['participantNames'] as Map<String, dynamic>?;
      if (participantNames != null && currentUserId != null) {
        for (final entry in participantNames.entries) {
          if (entry.key != currentUserId) {
            final String? name = entry.value as String?;
            if (name != null && name.trim().isNotEmpty) {
              chatTitle = name;
            }
            break;
          }
        }
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomView(
          chatId: chatId,
          chatTitle: chatTitle,
          isGroup: isGroup,
        ),
      ),
    );
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return "Just now";
    final now = DateTime.now();
    final difference = now.difference(timestamp.toDate());
    if (difference.inDays > 0) return "${difference.inDays}d ago";
    if (difference.inHours > 0) return "${difference.inHours}h ago";
    if (difference.inMinutes > 0) return "${difference.inMinutes}m ago";
    return "Just now";
  }

  String? _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final parts = name.trim().split(RegExp(r'\\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    final initials = "$first$last".trim().toUpperCase();
    return initials.isEmpty ? null : initials;
  }

  _NotificationVisual _visualForType(String? type, String? actorName) {
    final initials = _initialsFromName(actorName);

    switch (type) {
      case 'comment':
        return _NotificationVisual(
          icon: Icons.chat_bubble_rounded,
          color: _tealAccent,
          initials: initials,
        );
      case 'message':
        return _NotificationVisual(
          icon: Icons.chat_bubble_outline,
          color: _tealAccent,
          initials: initials,
        );
      case 'helpful':
        return const _NotificationVisual(
          icon: Icons.favorite_border,
          color: Color(0xFFFF6B6B),
        );
      case 'friend_request':
        return _NotificationVisual(
          icon: Icons.person_add_alt_1_rounded,
          color: _tealAccent,
          initials: initials,
        );
      case 'friend_accept':
        return _NotificationVisual(
          icon: Icons.person_rounded,
          color: _tealAccent,
          initials: initials,
        );
      case 'market_order':
        return const _NotificationVisual(
          icon: Icons.storefront_outlined,
          color: _tealAccent,
        );
      default:
        return _NotificationVisual(
          icon: Icons.notifications_none,
          color: _tealAccent,
          initials: initials,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final Widget body = user == null
        ? const Center(
            child: Text("Please sign in to see notifications", style: TextStyle(color: Colors.white54)),
          )
        : StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('notifications')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _tealAccent));
              }
              if (snapshot.hasError) {
                return const Center(child: Text("Error loading notifications", style: TextStyle(color: Colors.white54)));
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text("No notifications yet", style: TextStyle(color: Colors.white38)),
                );
              }

              final newDocs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['isRead'] != true;
              }).toList();
              final earlierDocs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['isRead'] == true;
              }).toList();

              return ListView(
                physics: const BouncingScrollPhysics(),
                padding: pagePadding(context),
                children: [
                  const SizedBox(height: 20),
                  if (newDocs.isNotEmpty) ...[
                    const Text(
                      "New",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 15),
                    ...newDocs.map(_buildNotificationTile),
                  ],
                  if (earlierDocs.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      "Earlier",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 15),
                    ...earlierDocs.map(_buildNotificationTile),
                  ],
                  const SizedBox(height: 20),
                ],
              );
            },
          );

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Notifications",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              "Stay updated with your activity",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
          ],
        ),
        actions: [
          if (user != null)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('notifications')
                  .where('isRead', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                final unreadCount = snapshot.data?.docs.length ?? 0;
                final bool canMarkAll = unreadCount > 0;
                return TextButton(
                  onPressed: canMarkAll ? _markAllRead : null,
                  child: Text(
                    "Mark all read",
                    style: TextStyle(
                      color: canMarkAll ? _tealAccent : Colors.white24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: body,
      ),
    );
  }

  Widget _buildNotificationTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final String title = data['title'] ?? "Notification";
    final String subtitle = data['body'] ?? "";
    final bool isRead = data['isRead'] == true;
    final String time = _timeAgo(data['createdAt'] as Timestamp?);
    final String? actorName = data['actorName'];
    final String? type = data['type'];

    final visual = _visualForType(type, actorName);

    return PressableScale(
      onTap: () => _handleNotificationTap(doc),
      borderRadius: BorderRadius.circular(15),
      pressedScale: 0.98,
      child: NotificationTile(
        title: title,
        subtitle: subtitle,
        time: time,
        icon: visual.icon,
        iconColor: visual.color,
        initials: visual.initials,
        isNew: !isRead,
      ),
    );
  }
}

class _NotificationVisual {
  final IconData icon;
  final Color color;
  final String? initials;

  const _NotificationVisual({
    required this.icon,
    required this.color,
    this.initials,
  });
}


