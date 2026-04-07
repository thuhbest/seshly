import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:seshly/widgets/pressable_scale.dart';
import 'package:seshly/widgets/responsive.dart';

import '../widgets/message_tile.dart';
import '../widgets/new_chat_sheet.dart';
import 'chat_room_view.dart';

class MessagesView extends StatefulWidget {
  const MessagesView({super.key});

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide =
            constraints.maxWidth >= ResponsiveBreakpoints.desktop;
        final listPanel = _buildListPanel(
          context,
          currentUserId,
          isWide: isWide,
          cardColor: cardColor,
        );

        return Scaffold(
          backgroundColor: backgroundColor,
          body: SafeArea(
            child: isWide
                ? Row(
                    children: [
                      SizedBox(width: 380, child: listPanel),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Colors.white10,
                      ),
                      Expanded(child: _buildEmptyDetailPanel()),
                    ],
                  )
                : listPanel,
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot> _chatStream(
    String currentUserId, {
    required bool ordered,
  }) {
    Query query = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUserId);
    if (ordered) {
      query = query.orderBy('lastMessageTime', descending: true);
    }
    return query.snapshots();
  }

  Widget _buildListPanel(
    BuildContext context,
    String? currentUserId, {
    required bool isWide,
    required Color cardColor,
  }) {
    const Color tealAccent = Color(0xFF00C09E);
    final EdgeInsets panelPadding = isWide
        ? const EdgeInsets.symmetric(horizontal: 16)
        : pagePadding(context);
    return Padding(
      padding: panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          _buildTopBar(context, isWide: isWide, tealAccent: tealAccent),
          const SizedBox(height: 14),
          _buildSearchPanel(cardColor),
          const SizedBox(height: 16),
          Expanded(
            child: currentUserId == null
                ? const Center(
                    child: Text(
                      "Please sign in to view messages",
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: _chatStream(currentUserId, ordered: true),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        debugPrint("Firestore Error: ${snapshot.error}");
                        return StreamBuilder<QuerySnapshot>(
                          stream: _chatStream(currentUserId, ordered: false),
                          builder: (context, fallbackSnapshot) {
                            if (fallbackSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: tealAccent,
                                ),
                              );
                            }
                            final fallbackChats =
                                fallbackSnapshot.data?.docs ?? [];
                            return _buildChatList(
                              context,
                              fallbackChats,
                              currentUserId,
                            );
                          },
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: tealAccent),
                        );
                      }

                      final chats = snapshot.data?.docs ?? [];
                      return _buildChatList(context, chats, currentUserId);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool isWide,
    required Color tealAccent,
  }) {
    return Row(
      children: [
        if (!isWide) ...[
          PressableScale(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(999),
            pressedScale: 0.92,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        const Expanded(
          child: Text(
            "Messages",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        PressableScale(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const NewChatSheet(),
          ),
          borderRadius: BorderRadius.circular(14),
          pressedScale: 0.92,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: tealAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tealAccent.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_comment_outlined, color: tealAccent, size: 18),
                const SizedBox(width: 8),
                Text(
                  'New chat',
                  style: TextStyle(
                    color: tealAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPanel(Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        decoration: InputDecoration(
          icon: const Icon(Icons.search, color: Colors.white54, size: 20),
          hintText: "Search messages",
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
          border: InputBorder.none,
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
        ),
      ),
    );
  }

  Widget _buildEmptyDetailPanel() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF1E243A).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            const Text(
              "Select a chat to preview",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Pick a conversation on the left to keep chatting without losing context.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(
    BuildContext context,
    List<QueryDocumentSnapshot> chats,
    String currentUserId,
  ) {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final visibleChats = chats.where((chat) {
      if (normalizedQuery.isEmpty) return true;
      final data = chat.data() as Map<String, dynamic>;
      final title = _chatNameFor(data, currentUserId).toLowerCase();
      final lastMessage = (data['lastMessage'] ?? '').toString().toLowerCase();
      return title.contains(normalizedQuery) ||
          lastMessage.contains(normalizedQuery);
    }).toList();

    if (visibleChats.isEmpty) {
      final bool hasSearch = normalizedQuery.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasSearch
                  ? Icons.search_off_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 70,
              color: Colors.white.withValues(alpha: 0.05),
            ),
            const SizedBox(height: 20),
            Text(
              hasSearch ? "No matching chats" : "No conversations yet",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hasSearch
                  ? "Try a different name or keyword."
                  : "Use the new chat button to message\na friend or create a study group.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: visibleChats.length,
      itemBuilder: (context, index) {
        final chatData = visibleChats[index].data() as Map<String, dynamic>;
        final chatId = visibleChats[index].id;
        final isGroup = chatData['isGroup'] ?? false;
        final chatName = _chatNameFor(chatData, currentUserId);

        final String? otherUserId = isGroup
            ? null
            : _getOtherUserId(chatData, currentUserId);
        final int groupSize = (chatData['participants'] as List?)?.length ?? 0;
        final int unreadCount = _toInt(
          _asStringDynamicMap(chatData['unreadCounts'])[currentUserId],
        );
        final Timestamp? lastMessageTime = _asTimestamp(
          chatData['lastMessageTime'],
        );

        final tile = MessageTile(
          title: chatName,
          subtitle: chatData['lastMessage'] ?? "Tap to chat",
          time: _getTimeString(lastMessageTime),
          isGroup: isGroup,
          groupSize: groupSize,
          unreadCount: unreadCount,
        );

        if (otherUserId == null) {
          return PressableScale(
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
            borderRadius: BorderRadius.circular(16),
            pressedScale: 0.98,
            child: tile,
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(otherUserId)
              .snapshots(),
          builder: (context, userSnap) {
            final userData =
                userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final Timestamp? lastSeen =
                _asTimestamp(userData['lastSeenAt']) ??
                _asTimestamp(userData['lastLoginAt']);
            bool isOnline = userData['isOnline'] == true;
            if (!isOnline && lastSeen != null) {
              final minutes = DateTime.now()
                  .difference(lastSeen.toDate())
                  .inMinutes;
              if (minutes <= 2) {
                isOnline = true;
              }
            }

            final String presenceLabel = isOnline
                ? "Online"
                : "Last seen ${_timeAgo(lastSeen)}";

            return PressableScale(
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
              borderRadius: BorderRadius.circular(16),
              pressedScale: 0.98,
              child: MessageTile(
                title: chatName,
                subtitle: chatData['lastMessage'] ?? "Tap to chat",
                time: _getTimeString(lastMessageTime),
                isGroup: isGroup,
                groupSize: groupSize,
                unreadCount: unreadCount,
                isOnline: isOnline,
                presenceLabel: presenceLabel,
              ),
            );
          },
        );
      },
    );
  }

  String _chatNameFor(Map<String, dynamic> chatData, String currentUserId) {
    final bool isGroup = chatData['isGroup'] == true;
    if (isGroup) {
      return (chatData['groupName'] ?? "Group").toString();
    }

    String chatName = "Seshly User";
    if (chatData['participantNames'] != null) {
      final namesMap = _asStringDynamicMap(chatData['participantNames']);
      namesMap.forEach((uid, name) {
        if (uid != currentUserId) chatName = name.toString();
      });
    }
    return chatName;
  }

  Timestamp? _asTimestamp(dynamic value) {
    if (value is Timestamp) return value;
    return null;
  }

  String _getTimeString(Timestamp? timestamp) {
    if (timestamp == null) return "";
    final date = timestamp.toDate();
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
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

  String? _getOtherUserId(
    Map<String, dynamic> chatData,
    String? currentUserId,
  ) {
    if (currentUserId == null) return null;
    final participants = chatData['participants'];
    if (participants is! List) return null;
    for (final participant in participants) {
      if (participant != currentUserId) return participant.toString();
    }
    return null;
  }
}
