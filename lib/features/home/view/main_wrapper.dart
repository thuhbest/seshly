import 'package:flutter/material.dart';
import 'package:seshly/features/home/view/home_view.dart';
import 'package:seshly/features/sesh/view/sesh_view.dart';
import 'package:seshly/features/home/widgets/custom_bottome_nav.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;

  // This list must match the order of your items in CustomBottomNav
  final List<Widget> _pages = [
    const HomeView(), // Index 0: Home
    const SeshView(), // Index 1: Sesh AI
    const Scaffold(body: Center(child: Text("Friends Screen", style: TextStyle(color: Colors.white)))), // Index 2
    const Scaffold(body: Center(child: Text("Calendar Screen", style: TextStyle(color: Colors.white)))), // Index 3
    const ProfilePlaceholder(), // Index 4: Profile with Sign Out test
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps all pages "alive" in the background
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
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

// Simple placeholder for the Profile tab so you can test Sign Out
class ProfilePlaceholder extends StatelessWidget {
  const ProfilePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C09E)),
        onPressed: () => FirebaseAuth.instance.signOut(),
        child: const Text("Sign Out", style: TextStyle(color: Color(0xFF0F142B))),
      ),
    );
  }
}