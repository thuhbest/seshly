import 'package:flutter/material.dart';
import 'package:seshly/features/home/view/home_view.dart';
import 'package:seshly/features/sesh/view/sesh_view.dart';
import 'package:seshly/features/home/widgets/custom_bottome_nav.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:seshly/services/auth_service.dart';
import 'package:seshly/services/notification_service.dart';

// 1. Import the FriendsView
import 'package:seshly/features/friends/view/friends_view.dart';

// 2. Import CalendarView
import 'package:seshly/features/calendar/view/calendar_view.dart';

// 3. Import profile and settings view
import 'package:seshly/features/profile/view/profile_view.dart';

// 4. Import FindTutorView
import 'package:seshly/features/tutors/view/find_tutor_view.dart';

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final ValueNotifier<int> _homeRefreshTick = ValueNotifier<int>(0);
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();
  late final List<Widget> _pages;
  bool _notificationsInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // This list now includes your real FriendsView at Index 2
    _pages = [
      HomeView(refreshSignal: _homeRefreshTick), // Index 0: Home
      const SeshView(), // Index 1: Sesh AI
      const FriendsView(), // Index 2: Real Friends Screen
      const CalendarView(), // Index 3: Real Calendar Screen
      const ProfileView() // Index 4: Real profile and settings screen
    ];
    // ignore: unawaited_futures
    _updateDailyStreak();
    // ignore: unawaited_futures
    _initNotifications();
    // ignore: unawaited_futures
    _setPresence(isOnline: true);
  }

  Future<void> _updateDailyStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _authService.updateDailyStreak(user.uid);
    } catch (_) {
      // Avoid blocking the UI if streak update fails.
    }
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _notificationsInitialized = true;
    try {
      await _notificationService.initForUser(user);
    } catch (_) {
      // Ignore notification init failures to avoid blocking the app shell.
    }
  }

  Future<void> _setPresence({required bool isOnline}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'isOnline': isOnline,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: unawaited_futures
      _setPresence(isOnline: true);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // ignore: unawaited_futures
      _setPresence(isOnline: false);
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ignore: unawaited_futures
    _setPresence(isOnline: false);
    _homeRefreshTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      // IndexedStack keeps all pages "alive" in the background
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // FloatingActionButton logic - Updated to navigate to FindTutorView
      floatingActionButton: _currentIndex == 0 
      ? FloatingActionButton(
          backgroundColor: const Color(0xFF00C09E),
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const FindTutorView()));
          },
          child: const Icon(Icons.person_add_alt_1, color: Colors.white),
        )
      : null,
      bottomNavigationBar: CustomBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (index == 0) {
            _homeRefreshTick.value++;
          }
          if (_currentIndex != index) {
            setState(() {
              _currentIndex = index;
            });
          }
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
