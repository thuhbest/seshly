import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../friend/widgets/friend_card.dart';
import '../mentor/widgets/mentor_card.dart';
import '../mentor/widgets/goals_card.dart';
import '../messages/view/messages_view.dart';
import '../widgets/leaderboard_card.dart';
import '../widgets/friend_requests_dialog.dart';

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

  // 🔥 RESTORED YOUR ORIGINAL SEARCH LOGIC EXACTLY
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
      final lowercaseQuery = query.toLowerCase();
      final uppercaseQuery = query.toUpperCase();

      // Check if the query looks like a Student Number (contains numbers)
      bool isPotentialStudentNumber = RegExp(r'[0-9]').hasMatch(query);

      if (isPotentialStudentNumber) {
        // High priority on Student Number search
        _searchResults = FirebaseFirestore.instance
            .collection('users')
            .where('studentNumber', isGreaterThanOrEqualTo: uppercaseQuery)
            .where('studentNumber', isLessThanOrEqualTo: '$uppercaseQuery\uf8ff')
            .limit(20)
            .snapshots();
      } else {
        // High priority on Name search
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

  @override
  Widget build(BuildContext context) {
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
                    ScaleButton(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => FriendRequestsDialog(onRequestHandled: _loadFriendRequestCount),
                        );
                      },
                      child: _headerBadgeIcon(Icons.person_add_outlined, _friendRequestCount.toString()),
                    ),
                    ScaleButton(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MessagesView())),
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
        return SingleChildScrollView(physics: const BouncingScrollPhysics(), child: _buildMentorshipTab());
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
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(friendId).get(),
              builder: (context, friendSnap) {
                if (!friendSnap.hasData) return const SizedBox.shrink();
                final data = friendSnap.data!.data() as Map<String, dynamic>;
                return FriendCard(
                  name: data['fullName'] ?? 'Student',
                  id: data['studentNumber'] ?? '',
                  year: data['levelOfStudy'] ?? '',
                  streak: (data['streak'] ?? 0).toString(),
                  mins: (data['seshMinutes'] ?? 0).toString(),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSearchResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: _searchResults,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No users found", style: TextStyle(color: Colors.white38)));
        }
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final userDoc = snapshot.data!.docs[index];
            if (userDoc.id == FirebaseAuth.instance.currentUser?.uid) return const SizedBox.shrink();
            return SearchUserResultCard(
              userData: userDoc.data() as Map<String, dynamic>,
              userId: userDoc.id,
              onAddFriend: () => _sendFriendRequest(userDoc.id),
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
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
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

  const SearchUserResultCard({super.key, required this.userData, required this.userId, required this.onAddFriend});

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
                Text('${userData['studentNumber'] ?? ''} • ${userData['levelOfStudy'] ?? ''}', 
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
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
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}