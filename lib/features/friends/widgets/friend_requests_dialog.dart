import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../view/friends_view.dart'; // Import ScaleButton

class FriendRequestsDialog extends StatefulWidget {
  final VoidCallback? onRequestHandled;
  
  const FriendRequestsDialog({super.key, this.onRequestHandled});

  @override
  State<FriendRequestsDialog> createState() => _FriendRequestsDialogState();
}

class _FriendRequestsDialogState extends State<FriendRequestsDialog> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late Stream<QuerySnapshot> _friendRequestsStream;

  @override
  void initState() {
    super.initState();
    _loadFriendRequests();
  }

  void _loadFriendRequests() {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId != null) {
      _friendRequestsStream = _firestore
          .collection('friend_requests')
          .where('toUserID', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else {
      _friendRequestsStream = const Stream.empty();
    }
  }

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data();
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  Future<List<String>> _getMutualFriends(String userId) async {
    try {
      final currentUserId = _auth.currentUser!.uid;
      
      // Get current user's friends
      final currentUserFriends = await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .get();
      
      // Get other user's friends
      final otherUserFriends = await _firestore
          .collection('users')
          .doc(userId)
          .collection('friends')
          .get();
      
      // Find intersection
      final currentFriendIds = currentUserFriends.docs.map((doc) => doc.id).toSet();
      final otherFriendIds = otherUserFriends.docs.map((doc) => doc.id).toSet();
      final mutualIds = currentFriendIds.intersection(otherFriendIds);
      
      // Get names of mutual friends
      final mutualFriends = <String>[];
      for (final id in mutualIds) {
        final userDoc = await _firestore.collection('users').doc(id).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          mutualFriends.add(data?['displayName'] ?? 'Unknown');
        }
      }
      
      return mutualFriends;
    } catch (e) {
      print('Error getting mutual friends: $e');
      return [];
    }
  }

  Future<void> _handleFriendRequest(String requestId, String fromUserId, bool accept) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // Update the request status
      await _firestore.collection('friend_requests').doc(requestId).update({
        'status': accept ? 'accepted' : 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // If accepted, add to friends collection
      if (accept) {
        final currentUserId = currentUser.uid;
        
        // Add to user's friends list
        await _firestore.collection('users').doc(currentUserId).collection('friends').doc(fromUserId).set({
          'addedAt': FieldValue.serverTimestamp(),
        });

        // Add current user to requester's friends list
        await _firestore.collection('users').doc(fromUserId).collection('friends').doc(currentUserId).set({
          'addedAt': FieldValue.serverTimestamp(),
        });
      }

      // Call the callback to refresh the friend request count
      if (widget.onRequestHandled != null) {
        widget.onRequestHandled!();
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Friend request accepted!' : 'Friend request declined'),
          backgroundColor: accept ? const Color(0xFF00C09E) : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error handling friend request: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${accept ? 'accept' : 'decline'} friend request'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _getTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Recently';
    
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildRequestItem(String requestId, Map<String, dynamic> requestData, Map<String, dynamic> userData) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    
    final displayName = userData['displayName'] ?? 'Unknown User';
    final year = userData['year'] ?? '';
    final userId = userData['id'] ?? requestData['fromUserID'];
    final major = userData['major'] ?? '';

    return FutureBuilder<List<String>>(
      future: _getMutualFriends(requestData['fromUserID']),
      builder: (context, snapshot) {
        final mutualFriends = snapshot.data ?? [];
        final mutualText = mutualFriends.isEmpty 
            ? 'No mutual friends' 
            : mutualFriends.length == 1 
                ? '1 mutual friend' 
                : '${mutualFriends.length} mutual friends';

        return Container(
          margin: const EdgeInsets.only(bottom: 15),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: tealAccent.withValues(alpha: 0.1),
                    radius: 22,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (userId.isNotEmpty && year.isNotEmpty)
                          Text(
                            '$userId • $year',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        if (major.isNotEmpty)
                          Text(
                            major,
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        Text(
                          mutualText,
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        Text(
                          _getTimeAgo(requestData['createdAt'] as Timestamp?),
                          style: const TextStyle(color: Color(0x61FFFFFF), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ScaleButton(
                      onTap: () => _handleFriendRequest(requestId, requestData['fromUserID'], true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: tealAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              "Accept",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ScaleButton(
                      onTap: () => _handleFriendRequest(requestId, requestData['fromUserID'], false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0x33FFFFFF)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              "Decline",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF161B30);

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Friend Requests",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ScaleButton(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0x1AFFFFFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.close, color: Colors.white54, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Tab Indicator
            StreamBuilder<QuerySnapshot>(
              stream: _friendRequestsStream,
              builder: (context, snapshot) {
                final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Received",
                          style: TextStyle(
                            color: tealAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (count > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tealAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              count.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Container(height: 2, width: 80, color: tealAccent),
                  ],
                );
              },
            ),
            const SizedBox(height: 25),

            // Request List
            StreamBuilder<QuerySnapshot>(
              stream: _friendRequestsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: tealAccent,
                      strokeWidth: 2,
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.person_add_disabled,
                            color: Colors.white54,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No pending friend requests',
                            style: TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When someone sends you a request,\nit will appear here',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final requests = snapshot.data!.docs;

                return SizedBox(
                  height: 400,
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      final requestData = request.data() as Map<String, dynamic>;
                      final requestId = request.id;

                      return FutureBuilder<Map<String, dynamic>?>(
                        future: _getUserData(requestData['fromUserID']),
                        builder: (context, userSnapshot) {
                          if (userSnapshot.connectionState == ConnectionState.waiting) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Color(0xFF2A3149),
                                    child: Icon(Icons.person, color: Colors.white54),
                                  ),
                                  SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 100,
                                          height: 16,
                                          child: LinearProgressIndicator(
                                            backgroundColor: Color(0xFF2A3149),
                                            color: Color(0xFF00C09E),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        SizedBox(
                                          width: 80,
                                          height: 12,
                                          child: LinearProgressIndicator(
                                            backgroundColor: Color(0xFF2A3149),
                                            color: Color(0xFF00C09E),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (!userSnapshot.hasData) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.redAccent,
                                    child: Icon(Icons.error, color: Colors.white),
                                  ),
                                  SizedBox(width: 15),
                                  Text(
                                    'User not found',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            );
                          }

                          final userData = userSnapshot.data!;
                          return _buildRequestItem(requestId, requestData, userData);
                        },
                      );
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}