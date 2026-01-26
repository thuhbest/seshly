import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StatsGrid extends StatelessWidget {
  final String userId;
  const StatsGrid({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return StreamBuilder<DocumentSnapshot>(
      // Stream 1: Real-time user data (Streak, SeshMinutes, and Points)
      stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, userSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          // Stream 2: Real-time post count logic (Questions Asked)
          stream: FirebaseFirestore.instance
              .collection('posts')
              .where('authorId', isEqualTo: userId)
              .snapshots(),
          builder: (context, postSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              // Stream 3: Real-time answers count (comments)
              stream: FirebaseFirestore.instance
                  .collectionGroup('comments')
                  .where('userId', isEqualTo: userId)
                  .snapshots(),
              builder: (context, answersSnapshot) {
                // Null safety check to prevent Red Screen
                final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
                final int questionCount = postSnapshot.data?.docs.length ?? 0;
                final int answerCount = answersSnapshot.data?.docs.length ?? 0;
                
                // 🔥 Fetching your exact Firebase fields with proper fallbacks
                final int streak = userData['streak'] ?? 0;
                final int seshMinutes = userData['seshMinutes'] ?? 0;
                final int replies = answerCount;

                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  childAspectRatio: 1.4, // Using current code's aspect ratio
                  children: [
                    _buildStatItem(
                      label: "Questions Asked",
                      value: questionCount.toString(),
                      icon: Icons.book_outlined,
                      color: tealAccent,
                    ),
                    _buildStatItem(
                      label: "Answers Given",
                      value: replies.toString(),
                      icon: Icons.stars_rounded, // Updated icon from current code
                      color: const Color(0xFFFFD700),
                    ),
                    _buildStatItem(
                      label: "SeshMinutes",
                      value: seshMinutes.toString(),
                      icon: Icons.bolt_rounded,
                      color: Colors.purpleAccent,
                    ),
                    // Choose which stat to display:
                    // Option 1: Study Streak from current code
                    _buildStatItem(
                      label: "Study Streak",
                      value: "$streak days",
                      icon: Icons.show_chart_rounded,
                      color: Colors.orangeAccent,
                    ),
                    // OR Option 2: Points from previous code (comment out one)
                    // _buildStatItem(
                    //   label: "Points Earned",
                    //   value: points.toString(),
                    //   icon: Icons.star_outline,
                    //   color: Colors.orangeAccent,
                    // ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5), // Reverted to your original withValues
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)), // Also fixed this one
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
