import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeController {
  final BuildContext context;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

  // State for the selected category chip
  String selectedCategory = "All";

  // State for the bottom navigation bar
  int currentIndex = 0;

  HomeController(this.context);

  // Function to update the category (will be called from the UI)
  void updateCategory(String category, Function setStateCallback) {
    setStateCallback(() {
      selectedCategory = category;
    });
    debugPrint("Category changed to: $category");
  }

  // Function to update the bottom nav tab
  void updateTab(int index, Function setStateCallback) {
    setStateCallback(() {
      currentIndex = index;
    });
    debugPrint("Tab changed to index: $index");
  }

  // Logic for the Floating Action Button
  void onAddFriendPressed() {
    debugPrint("Add Friend/Tutor button pressed");
    // Navigation logic for adding friends would go here
  }

  // This function creates a "Relevance Score" for every post
  Stream<List<Map<String, dynamic>>> getRankedPosts() {
    return _db.collection('posts').snapshots().map((snapshot) {
      List<Map<String, dynamic>> posts = snapshot.docs.map((doc) {
        var data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // MOCK USER DATA (In a real app, fetch this from the user's profile doc)
      List<String> userInterests = ["Calculus", "Mathematics", "Engineering"];
      List<String> userFriends = ["friend_uid_1", "friend_uid_2"];

      posts.sort((a, b) {
        double scoreA = _calculateScore(a, userInterests, userFriends);
        double scoreB = _calculateScore(b, userInterests, userFriends);

        // Sort by Score Descending (Highest relevance first)
        return scoreB.compareTo(scoreA);
      });

      return posts;
    });
  }

  double _calculateScore(Map<String, dynamic> post, List<String> interests, List<String> friends) {
    double score = 0.0;

    // --- RULE 1: RELEVANCE (Primary) ---
    if (interests.contains(post['subject'])) {
      score += 100.0; // Huge boost for "What I'm studying"
    }
    
    if (post['isUrgent'] == true) {
      score += 50.0; // Boost for "Stuck/Urgent"
    }

    // --- RULE 2: TIME (Secondary) ---
    Timestamp ts = post['createdAt'] ?? Timestamp.now();
    int minutesOld = DateTime.now().difference(ts.toDate()).inMinutes;
    // We subtract score based on age, but not enough to kill relevance
    // A 3-hour-old (180 mins) Calculus post still beats a fresh Philosophy post
    score -= (minutesOld * 0.1); 

    // --- RULE 3: RELATIONSHIP (Tertiary) ---
    if (friends.contains(post['authorId'])) {
      score += 15.0; // Light boost for friends/known people
    }

    return score;
  }
}