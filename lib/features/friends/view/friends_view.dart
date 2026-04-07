import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../friend/widgets/friend_card.dart';
import '../mentor/view/mentorship_hub.dart';
import '../messages/view/messages_view.dart';
import '../messages/view/chat_room_view.dart'; // 🔥 Added for navigation
import '../widgets/leaderboard_card.dart';
import '../widgets/friend_requests_dialog.dart';
import 'package:seshly/theme/seshly_theme.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/community_backend_service.dart';
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
  final CommunityBackendService _backend = CommunityBackendService.instance;

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
      bool isPotentialStudentNumber = RegExp(
        r'[0-9]',
      ).hasMatch(normalizedQuery);

      if (isEmailQuery) {
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where('emailLowercase', isGreaterThanOrEqualTo: lowercaseQuery)
            .where(
              'emailLowercase',
              isLessThanOrEqualTo: '$lowercaseQuery\uf8ff',
            )
            .limit(20)
            .snapshots();
      } else if (isPotentialStudentNumber) {
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where(
              'studentNumberLowercase',
              isGreaterThanOrEqualTo: lowercaseQuery,
            )
            .where(
              'studentNumberLowercase',
              isLessThanOrEqualTo: '$lowercaseQuery\uf8ff',
            )
            .limit(20)
            .snapshots();
      } else {
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where('fullNameLowercase', isGreaterThanOrEqualTo: lowercaseQuery)
            .where(
              'fullNameLowercase',
              isLessThanOrEqualTo: '$lowercaseQuery\uf8ff',
            )
            .limit(20)
            .snapshots();
      }
    });
  }

  Future<void> _sendFriendRequest(String targetUserId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid == targetUserId) return;

    try {
      await _backend.sendFriendRequest(targetUserId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request sent!'),
          backgroundColor: Color(0xFF00C09E),
        ),
      );
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'community',
        source: 'send_friend_request',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorService.instance.userMessageFor(
              error,
              fallback: 'Could not send a friend request right now.',
            ),
          ),
        ),
      );
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
    try {
      final chatId = await _backend.ensureDirectChat(friendId);
      if (!mounted || chatId.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatRoomView(
            chatId: chatId,
            chatTitle: friendName,
            isGroup: false,
          ),
        ),
      );
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'community',
        source: 'ensure_direct_chat',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorService.instance.userMessageFor(
              error,
              fallback: 'Could not open this chat right now.',
            ),
          ),
        ),
      );
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
            const SizedBox(height: 14),
            _buildHeaderBar(currentUserId),
            const SizedBox(height: 16),
            _buildSearchPanel(cardColor),
            const SizedBox(height: 14),
            _buildSegmentTabs(cardColor),
            const SizedBox(height: 18),
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
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('streak', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C09E)),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              "Leadership board will appear as soon as learners build streaks.",
              style: TextStyle(color: Colors.white38),
            ),
          );
        }

        final int currentUserRank = currentUserId == null
            ? 0
            : docs.indexWhere((doc) => doc.id == currentUserId) + 1;
        final Map<String, dynamic> leader =
            docs.first.data() as Map<String, dynamic>;
        final int leaderStreak = (leader['streak'] as num?)?.toInt() ?? 0;
        final int leaderXp = (leader['xp'] as num?)?.toInt() ?? 0;

        return ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E243A).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _leadershipMetric(
                    "Current leader",
                    (leader['fullName'] ?? 'Student').toString(),
                  ),
                  _leadershipMetric("Top streak", "$leaderStreak days"),
                  _leadershipMetric("Leader XP", "$leaderXp XP"),
                  _leadershipMetric(
                    "Your position",
                    currentUserRank == 0
                        ? "Outside top 50"
                        : "#$currentUserRank",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(docs.length, (index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final String major = (data['major'] ?? '').toString().trim();
              final String level =
                  (data['levelOfStudy'] ?? data['year'] ?? 'Student')
                      .toString();
              final String university = (data['university'] ?? 'Global learner')
                  .toString();
              final String subtitle = [
                university,
                if (major.isNotEmpty) major else level,
              ].join(' • ');
              return LeaderboardCard(
                rank: index + 1,
                name: (data['fullName'] ?? 'User').toString(),
                streak: (data['streak'] as num?)?.toInt() ?? 0,
                xp: (data['xp'] as num?)?.toInt() ?? 0,
                subtitle: subtitle,
                isUser: docs[index].id == currentUserId,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildHeaderBar(String? currentUserId) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Text(
            "Friends",
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildHeroActions(currentUserId),
      ],
    );
  }

  Widget _buildHeroActions(String? currentUserId) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleButton(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => FriendRequestsDialog(
                onRequestHandled: _loadFriendRequestCount,
              ),
            );
          },
          child: _headerBadgeIcon(
            Icons.person_add_outlined,
            _friendRequestCount.toString(),
          ),
        ),
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
                final unreadCounts = _asStringDynamicMap(data['unreadCounts']);
                final unreadForUser = unreadCounts[currentUserId];
                if (unreadForUser != null) {
                  totalUnread += _toInt(unreadForUser);
                }
              }
            }
            return ScaleButton(
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const MessagesView())),
              child: _headerBadgeIcon(
                Icons.chat_bubble_outline,
                totalUnread.toString(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSearchPanel(Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.white54),
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
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_isSearching)
            ScaleButton(
              onTap: _clearSearch,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentTabs(Color cardColor) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          _toggleButton("Friends", 0, Icons.groups_rounded),
          _toggleButton("Mentorship", 1, Icons.school_rounded),
          _toggleButton("Leadership", 2, Icons.emoji_events_outlined),
        ],
      ),
    );
  }

  Widget _leadershipMetric(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealFriendsList() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.groups_2_outlined,
            title: "No friends yet",
            subtitle: "Search for students and build your study circle here.",
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final friendId = snapshot.data!.docs[index].id;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(friendId)
                  .snapshots(),
              builder: (context, friendSnap) {
                if (!friendSnap.hasData) return const SizedBox.shrink();
                final data =
                    friendSnap.data!.data() as Map<String, dynamic>? ?? {};
                final friendName = (data['fullName'] ?? 'Student').toString();
                final Timestamp? lastSeen =
                    _asTimestamp(data['lastSeenAt']) ??
                    _asTimestamp(data['lastLoginAt']);
                bool isOnline = data['isOnline'] == true;
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
      return const Center(
        child: Text(
          "Sign in to search users",
          style: TextStyle(color: Colors.white38),
        ),
      );
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
        final friendIds =
            friendsSnapshot.data?.docs.map((doc) => doc.id).toSet() ?? {};
        return StreamBuilder<QuerySnapshot>(
          stream: outgoingRequestsStream,
          builder: (context, requestsSnapshot) {
            final requestedIds =
                requestsSnapshot.data?.docs
                    .map(
                      (doc) => (doc.data() as Map<String, dynamic>)['toUserID']
                          ?.toString(),
                    )
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
                  return _buildEmptyState(
                    icon: Icons.search_off_rounded,
                    title: "No users found",
                    subtitle: "Try a different name, student number, or email.",
                  );
                }
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final userDoc = snapshot.data!.docs[index];
                    if (userDoc.id == currentUserId) {
                      return const SizedBox.shrink();
                    }
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

  Widget _toggleButton(String label, int index, IconData icon) {
    bool isSelected = _selectedTab == index;
    return Expanded(
      child: ScaleButton(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF142A47), Color(0xFF1D2238)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: Colors.white.withValues(alpha: 0.1))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? SeshlyPalette.aqua : Colors.white54,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
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
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF00C09E), size: 22),
        ),
        if (count != "0")
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFF00C09E),
                shape: BoxShape.circle,
              ),
              child: Text(
                count,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E243A).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: SeshlyPalette.aqua, size: 34),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.4),
            ),
          ],
        ),
      ),
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
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        borderRadius: BorderRadius.circular(12),
      ),
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
                Text(
                  userData['fullName'] ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                border: Border.all(
                  color: const Color(0xFF00C09E).withValues(alpha: 0.4),
                ),
              ),
              child: const Text(
                'Friends',
                style: TextStyle(
                  color: Color(0xFF00C09E),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
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
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            ScaleButton(
              onTap: onAddFriend,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C09E),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Add Friend',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
