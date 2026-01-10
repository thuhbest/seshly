import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserAnswersView extends StatelessWidget {
  final String userId;
  const UserAnswersView({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "My Contributions",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 🔥 The Revolutionary CollectionGroup Query
        stream: FirebaseFirestore.instance
            .collectionGroup('comments')
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}", 
              style: const TextStyle(color: Colors.white54))
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: tealAccent));
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.maps_ugc_rounded, color: Colors.white.withValues(alpha: 0.1), size: 80),
                  const SizedBox(height: 16),
                  const Text(
                    "No answers yet.\nHelp a peer to earn XP!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final timestamp = data['createdAt'] as Timestamp?;
              final dateLabel = timestamp != null 
                  ? DateFormat('dd MMM yyyy').format(timestamp.toDate()) 
                  : "Recently";

              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tealAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            "ANSWER",
                            style: TextStyle(
                              color: tealAccent, 
                              fontSize: 10, 
                              fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                        Text(
                          dateLabel,
                          style: const TextStyle(color: Colors.white24, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      data['text'] ?? "",
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 14, 
                        height: 1.5
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10, thickness: 0.5),
                    const SizedBox(height: 8),
                    // Button to view the original post if needed
                    GestureDetector(
                      onTap: () {
                        // Logic to find parent post and navigate
                      },
                      child: Row(
                        children: [
                          Icon(Icons.link_rounded, color: tealAccent.withValues(alpha: 0.5), size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            "View original post",
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}