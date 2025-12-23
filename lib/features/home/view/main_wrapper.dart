import 'package:flutter/material.dart';
import 'package:seshly/features/home/view/home_view.dart';
import 'package:seshly/features/sesh/view/sesh_view.dart';
import 'package:seshly/features/home/widgets/custom_bottome_nav.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 1. Import the FriendsView
import 'package:seshly/features/friends/view/friends_view.dart';

// 2. Import CalendarView
import 'package:seshly/features/calendar/view/calendar_view.dart';

//3. Import profile and settings view
import 'package:seshly/features/profile/view/profile_view.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  // This list now includes your real FriendsView at Index 2
  final List<Widget> _pages = [
    const HomeView(), // Index 0: Home
    const SeshView(), // Index 1: Sesh AI
    const FriendsView(), // Index 2: Real Friends Screen
    const CalendarView(), // Index 3: Real Calendar Screen
    const ProfileView() //Index 4: Real profile and settings screen
  ];

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      // IndexedStack keeps all pages "alive" in the background
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // FloatingActionButton logic
      floatingActionButton: _currentIndex == 0 
      ? FloatingActionButton(
          backgroundColor: tealAccent,
          onPressed: () => debugPrint("Add Post/Tutor Pressed"),
          child: const Icon(Icons.person_add_alt_1, color: Colors.white),
        )
      : null,
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class ProfilePlaceholder extends StatelessWidget {
  const ProfilePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color navColor = Color(0xFF0F142B);

    return Center(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: tealAccent,
          foregroundColor: navColor,
        ),
        onPressed: () => FirebaseAuth.instance.signOut(),
        child: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}