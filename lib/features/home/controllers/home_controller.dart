import 'package:flutter/material.dart';

class HomeController {
  final BuildContext context;

  HomeController(this.context);

  // State for the selected category chip
  String selectedCategory = "All";

  // State for the bottom navigation bar
  int currentIndex = 0;

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
}