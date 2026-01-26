import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../friend/widgets/friend_card.dart';
import '../mentor/view/mentorship_hub.dart';
import '../messages/view/messages_view.dart';
import '../messages/view/chat_room_view.dart'; // 🔥 Added for navigation
import '../widgets/leaderboard_card.dart';
import '../widgets/friend_requests_dialog.dart';
import 'package:seshly/widgets/responsive.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class FriendsView extends StatefulWidget {
  const FriendsView({super.key});

  @override
  State<FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<FriendsView> {
  // 0: Friends, 1: Mentorship, 2: Rankings
  int _selectedTab = 0;
  int _friendRequestCount = 0;

  final TextEditingController _searchController = TextEditingController();
  Stream<QuerySnapshot>? _searchResults;
  bool _isSearching = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFriendRequestCount();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriendRequestCount() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        final snapshot = await FirebaseFirestore.instance
            .collection('friend_requests')
            .where('toUserID', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'pending')
            .get();

        if (mounted) {
          setState(() {
            _friendRequestCount = snapshot.docs.length;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading friend request count: $e');
    }
  }

  void _performSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      final normalizedQuery = query.trim();
      final lowercaseQuery = normalizedQuery.toLowerCase();

      bool isEmailQuery = lowercaseQuery.contains('@');
      bool isPotentialStudentNumber = RegExp(r'[0-9]').hasMatch(normalizedQuery);

      if (isEmailQuery) {
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where('emailLowercase', isGreaterThanOrEqualTo: lowercaseQuery)
            .where('emailLowercase', isLessThanOrEqualTo: '$lowercaseQuery\uf8ff')
            .limit(20)
            .snapshots();
      } else if (isPotentialStudentNumber) {
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where('studentNumberLowercase', isGreaterThanOrEqualTo: lowercaseQuery)
            .where('studentNumberLowercase', isLessThanOrEqualTo: '$lowercaseQuery\uf8ff')
            .limit(20)
            .snapshots();
      } else {
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where('fullNameLowercase', isGreaterThanOrEqualTo: lowercaseQuery)
            .where('fullNameLowercase', isLessThanOrEqualTo: '$lowercaseQuery\uf8ff')
            .limit(20)
            .snapshots();
      }
    });
  }

  Future<void> _sendFriendRequest(String targetUserId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid == targetUserId) return;

    try {
      final friendDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('friends')
          .doc(targetUserId)
          .get();
      if (friendDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are already friends.'), backgroundColor: Color(0xFF00C09E)),
        );
        return;
      }

      final existingRequest = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUserID', isEqualTo: currentUser.uid)
          .where('toUserID', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existingRequest.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request already sent'), backgroundColor: Colors.orange),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('friend_requests').add({
        'fromUserID': currentUser.uid,
        'toUserID': targetUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend request sent!'), backgroundColor: Color(0xFF00C09E)),
      );
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults = null;
      _isSearching = false;
      _currentQuery = '';
    });
  }

  // Helper to open a chat with a specific friend
  Future<void> _openChat(String friendId, String friendName) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Search for existing chat
    final query = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .get();

    String? existingChatId;
    for (var doc in query.docs) {
      List participants = doc['participants'];
      if (participants.contains(friendId) && participants.length == 2) {
        existingChatId = doc.id;
        break;
      }
    }

    if (!mounted) return;
    if (existingChatId != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatRoomView(chatId: existingChatId!, chatTitle: friendName, isGroup: false),
      ));
    } else {
      // Create new chat document if it doesn't exist
      final newChat = await FirebaseFirestore.instance.collection('chats').add({
        'participants': [currentUserId, friendId],
        'participantNames': {currentUserId: 'Me', friendId: friendName}, // Replace 'Me' with actual name logic
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'isGroup': false,
        'unreadCounts': {currentUserId: 0, friendId: 0}, // 🔥 Initialize unread counts
      });
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatRoomView(chatId: newChat.id, chatTitle: friendName, isGroup: false),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color cardColor = Color(0xFF1E243A);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return SafeArea(
      child: Padding(
        padding: pagePadding(context),
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
                    ScaleButton(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => FriendRequestsDialog(onRequestHandled: _loadFriendRequestCount),
                        );
                      },
                      child: _headerBadgeIcon(Icons.person_add_outlined, _friendRequestCount.toString()),
                    ),
                    // 🔥 UPDATED: Logic to show real sum of UNREAD messages
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .where('participants', arrayContains: currentUserId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        int totalUnread = 0;
                        if (snapshot.hasData) {
                          for (var doc in snapshot.data!.docs) {
                            final data = doc.data() as Map<String, dynamic>;
                            // Sum up the unread counts assigned specifically to the current user
                            if (data['unreadCounts'] != null && data['unreadCounts'][currentUserId] != null) {
                              totalUnread += (data['unreadCounts'][currentUserId] as int);
                            }
                          }
                        }
                        return ScaleButton(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MessagesView())),
                          child: _headerBadgeIcon(Icons.chat_bubble_outline, totalUnread.toString()),
                        );
                      },
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(15)),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.white54),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        final query = value.trim();
                        if (query != _currentQuery) {
                          _currentQuery = query;
                          _performSearch(query);
                        }
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Search by name, student number, or email",
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  if (_isSearching)
                    ScaleButton(
                      onTap: _clearSearch,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.close, color: Colors.white54, size: 18),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: cardColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  _toggleButton("Friends", 0),
                  _toggleButton("Mentorship", 1),
                  _toggleButton("Rankings", 2),
                ],
              ),
            ),
            const SizedBox(height: 25),
            Expanded(
              child: _isSearching ? _buildSearchResults() : _buildActiveTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTab() {
    switch (_selectedTab) {
      case 1:
        return _buildMentorshipTab();
      case 2:
        return _buildLeaderboardTab();
      default:
        return _buildRealFriendsList();
    }
  }

  Widget _buildLeaderboardTab() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').orderBy('streak', descending: true).limit(50).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
        final docs = snapshot.data!.docs;
        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return LeaderboardCard(
              rank: index + 1,
              name: data['fullName'] ?? 'User',
              streak: (data['streak'] ?? 0).toString(),
              isUser: docs[index].id == currentUserId,
            );
          },
        );
      },
    );
  }

  Widget _buildRealFriendsList() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("Add friends to see them here", style: TextStyle(color: Colors.white38)));
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final friendId = snapshot.data!.docs[index].id;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(friendId).snapshots(),
              builder: (context, friendSnap) {
                if (!friendSnap.hasData) return const SizedBox.shrink();
                final data = friendSnap.data!.data() as Map<String, dynamic>? ?? {};
                final friendName = (data['fullName'] ?? 'Student').toString();
                final Timestamp? lastSeen = _asTimestamp(data['lastSeenAt']) ?? _asTimestamp(data['lastLoginAt']);
                bool isOnline = data['isOnline'] == true;
                if (!isOnline && lastSeen != null) {
                  final minutes = DateTime.now().difference(lastSeen.toDate()).inMinutes;
                  if (minutes <= 2) {
                    isOnline = true;
                  }
                }

                final String presenceLabel = isOnline ? "Online" : "Last seen ${_timeAgo(lastSeen)}";

                return FriendCard(
                  name: friendName,
                  id: data['studentNumber'] ?? '',
                  year: data['levelOfStudy'] ?? '',
                  streak: (data['streak'] ?? 0).toString(),
                  mins: (data['seshMinutes'] ?? 0).toString(),
                  isOnline: isOnline,
                  presenceLabel: presenceLabel,
                  // ?? UPDATED: Click on message icon/button in card opens chat
                  onMessage: () => _openChat(friendId, friendName),
                );
              },
            );
          },
        );
      },
    );
  }

  Timestamp? _asTimestamp(dynamic value) {
    if (value is Timestamp) return value;
    return null;
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

  Widget _buildSearchResults() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Center(child: Text("Sign in to search users", style: TextStyle(color: Colors.white38)));
    }

    final friendsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('friends')
        .snapshots();
    final outgoingRequestsStream = FirebaseFirestore.instance
        .collection('friend_requests')
        .where('fromUserID', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: friendsStream,
      builder: (context, friendsSnapshot) {
        final friendIds = friendsSnapshot.data?.docs.map((doc) => doc.id).toSet() ?? {};
        return StreamBuilder<QuerySnapshot>(
          stream: outgoingRequestsStream,
          builder: (context, requestsSnapshot) {
            final requestedIds = requestsSnapshot.data?.docs
                    .map((doc) => (doc.data() as Map<String, dynamic>)['toUserID']?.toString())
                    .where((id) => id != null)
                    .cast<String>()
                    .toSet() ??
                {};
            return StreamBuilder<QuerySnapshot>(
              stream: _searchResults,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No users found", style: TextStyle(color: Colors.white38)));
                }
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final userDoc = snapshot.data!.docs[index];
                    if (userDoc.id == currentUserId) return const SizedBox.shrink();
                    final isFriend = friendIds.contains(userDoc.id);
                    final isRequested = requestedIds.contains(userDoc.id);
                    return SearchUserResultCard(
                      userData: userDoc.data() as Map<String, dynamic>,
                      userId: userDoc.id,
                      isFriend: isFriend,
                      isRequested: isRequested,
                      onAddFriend: () => _sendFriendRequest(userDoc.id),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _toggleButton(String label, int index) {
    bool isSelected = _selectedTab == index;
    return Expanded(
      child: ScaleButton(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E243A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 0.1)) : null,
          ),
          child: Center(
            child: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  Widget _buildMentorshipTab() {
    return MentorshipHub(onMessageUser: _openChat);
  }

  Widget _headerBadgeIcon(IconData icon, String count) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF00C09E), size: 22),
        ),
        if (count != "0")
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Color(0xFF00C09E), shape: BoxShape.circle),
              child: Text(count, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          )
      ],
    );
  }
}

class SearchUserResultCard extends StatelessWidget {
  final Map<String, dynamic> userData;
  final String userId;
  final VoidCallback onAddFriend;
  final bool isFriend;
  final bool isRequested;

  const SearchUserResultCard({
    super.key,
    required this.userData,
    required this.userId,
    required this.onAddFriend,
    this.isFriend = false,
    this.isRequested = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E243A), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF00C09E).withValues(alpha: 0.1),
            child: const Icon(Icons.person_outline, color: Color(0xFF00C09E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userData['fullName'] ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(
                  '${userData['studentNumber'] ?? ''} - ${userData['levelOfStudy'] ?? ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isFriend)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF00C09E).withValues(alpha: 0.4)),
              ),
              child: const Text(
                'Friends',
                style: TextStyle(color: Color(0xFF00C09E), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            )
          else if (isRequested)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Text(
                'Requested',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            )
          else
            ScaleButton(
              onTap: onAddFriend,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF00C09E), borderRadius: BorderRadius.circular(20)),
                child: const Text('Add Friend', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const ScaleButton({super.key, required this.child, required this.onTap});

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> {
  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: widget.onTap,
      pressedScale: 0.95,
      child: widget.child,
    );
  }
}

