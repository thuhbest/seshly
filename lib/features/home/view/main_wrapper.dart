import 'package:flutter/material.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/features/home/view/home_view.dart';
import 'package:seshly/features/sesh/view/sesh_view.dart';
import 'package:seshly/features/home/widgets/custom_bottome_nav.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:seshly/features/profile/view/tutor_application_view.dart';
import 'package:seshly/features/profile/view/tutor_stats_view.dart';
import 'package:seshly/features/profile/view/instant_tutor_mode_account_view.dart';
import 'package:seshly/services/auth_service.dart';
import 'package:seshly/services/notification_service.dart';
import 'package:seshly/services/tutor_identity_service.dart';
import 'package:seshly/features/tutors/widgets/gold_tick_badge.dart';
import 'package:seshly/features/tutors/widgets/tutor_review_prompt_listener.dart';
import 'package:seshly/widgets/responsive.dart';

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
  bool _notificationsInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ignore: unawaited_futures
    _updateDailyStreak();
    // ignore: unawaited_futures
    _initNotifications();
    // ignore: unawaited_futures
    _setPresence(isOnline: true);
  }

  Future<void> _updateDailyStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      await _authService.updateDailyStreak(user.uid);
    } catch (_) {
      // Avoid blocking the UI if streak update fails.
    }
  }

  Future<void> _initNotifications() async {
    if (_notificationsInitialized) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    _notificationsInitialized = true;
    try {
      await _notificationService.initForUser(user);
    } catch (_) {
      // Ignore notification init failures to avoid blocking the app shell.
    }
  }

  Future<void> _setPresence({required bool isOnline}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': isOnline,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Presence is not required to enter the shell.
    }
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
    final session = AccessController.session(context);
    final bool isInstantTutorMode = session.identity.isInstantTutor;
    debugPrint(
      'MainWrapper: rendering ${isInstantTutorMode ? 'Instant Tutor shell' : 'full-account shell'} for uid=${session.userId}.',
    );
    final List<Widget> pages = _buildPages(
      isInstantTutorMode: isInstantTutorMode,
    );
    const Color backgroundColor = Color(0xFF0F142B);
    final Widget content = IndexedStack(index: _currentIndex, children: pages);

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide =
            constraints.maxWidth >= ResponsiveBreakpoints.desktop;
        final bool isExtended = constraints.maxWidth >= 1200;
        final Widget shellBody = Stack(
          children: [
            isWide
                ? Row(
                    children: [
                      NavigationRail(
                        backgroundColor: backgroundColor,
                        selectedIndex: _currentIndex,
                        onDestinationSelected: _handleNavTap,
                        extended: isExtended,
                        selectedIconTheme: const IconThemeData(
                          color: Color(0xFF00C09E),
                        ),
                        unselectedIconTheme: const IconThemeData(
                          color: Colors.white54,
                        ),
                        selectedLabelTextStyle: const TextStyle(
                          color: Color(0xFF00C09E),
                          fontWeight: FontWeight.bold,
                        ),
                        unselectedLabelTextStyle: const TextStyle(
                          color: Colors.white54,
                        ),
                        destinations: isInstantTutorMode
                            ? const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.home_filled),
                                  label: Text("Home"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.badge_outlined),
                                  label: Text("Instant Tutor"),
                                ),
                              ]
                            : const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.home_filled),
                                  label: Text("Home"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.auto_awesome_rounded),
                                  label: Text("Sesh"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.people_alt_outlined),
                                  label: Text("Friends"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.calendar_today_outlined),
                                  label: Text("Calendar"),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.person_outline),
                                  label: Text("Profile"),
                                ),
                              ],
                      ),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Colors.white10,
                      ),
                      Expanded(
                        child: ResponsiveCenter(
                          padding: EdgeInsets.zero,
                          child: content,
                        ),
                      ),
                    ],
                  )
                : content,
            if (!isInstantTutorMode) const TutorReviewPromptListener(),
          ],
        );

        return Scaffold(
          backgroundColor: backgroundColor,
          body: shellBody,
          floatingActionButton: _buildShellFab(context),
          bottomNavigationBar: isWide
              ? null
              : isInstantTutorMode
              ? _InstantTutorModeBottomNav(
                  currentIndex: _currentIndex,
                  onTap: _handleNavTap,
                )
              : CustomBottomNav(
                  currentIndex: _currentIndex,
                  onTap: _handleNavTap,
                ),
        );
      },
    );
  }

  List<Widget> _buildPages({required bool isInstantTutorMode}) {
    if (isInstantTutorMode) {
      return [
        HomeView(refreshSignal: _homeRefreshTick),
        const InstantTutorModeAccountView(),
      ];
    }

    return [
      HomeView(refreshSignal: _homeRefreshTick),
      const SeshView(),
      const FriendsView(),
      const CalendarView(),
      const ProfileView(),
    ];
  }

  void _handleNavTap(int index) {
    final bool isInstantTutorMode = AccessController.isInstantTutorModeFor(
      context,
    );
    final int maxIndex = isInstantTutorMode ? 1 : 4;
    if (index < 0 || index > maxIndex) return;
    if (index == 0) {
      _homeRefreshTick.value++;
    }
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  Widget? _buildShellFab(BuildContext context) {
    if (_currentIndex != 0) return null;
    final session = AccessController.session(context);
    if (session.identity.isInstantTutor) {
      return _buildFindTutorFab(
        context,
        userData: session.userData,
        prioritizeInstantTutorMode: true,
      );
    }
    if (session.userId.isEmpty) {
      return _buildFindTutorFab(context);
    }
    return _buildFindTutorFab(context, userData: session.userData);
  }

  Widget _buildFindTutorFab(
    BuildContext context, {
    Map<String, dynamic> userData = const {},
    bool prioritizeInstantTutorMode = false,
  }) {
    return FloatingActionButton.extended(
      heroTag: 'find-tutor-fab',
      tooltip: prioritizeInstantTutorMode
          ? 'Open live tutor discovery'
          : 'Find a tutor',
      backgroundColor: prioritizeInstantTutorMode
          ? const Color(0xFF18E3C1)
          : const Color(0xFF00C09E),
      foregroundColor: const Color(0xFF0F142B),
      elevation: prioritizeInstantTutorMode ? 14 : 6,
      highlightElevation: prioritizeInstantTutorMode ? 18 : 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onPressed: () => _handleTutorEntry(context, userData),
      icon: Icon(
        prioritizeInstantTutorMode
            ? Icons.bolt_rounded
            : Icons.person_search_rounded,
      ),
      label: Text(
        prioritizeInstantTutorMode ? 'Find Tutor Now' : 'Find Tutor',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  void _handleTutorEntry(BuildContext context, Map<String, dynamic> userData) {
    final session = AccessController.session(context);
    if (session.identity.isInstantTutor) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FindTutorView()),
      );
      return;
    }

    final tutor = session.tutor;
    if (!tutor.canOpenTutorDesk) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FindTutorView()),
      );
      return;
    }

    // Tutor stats and controls only surface after entering through Home.
    _openTutorHubSheet(context, tutor);
  }

  Future<void> _openTutorHubSheet(
    BuildContext context,
    TutorIdentity tutor,
  ) async {
    final bool isApproved = tutor.isApproved;
    final int sessionsCompleted = tutor.performance.sessionsCompleted;
    final int learnersHelped = tutor.performance.learnersHelped;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E243A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget signal({required String label, required String value}) {
          return Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F142B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      'Tutor Hub',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (tutor.goldTick.badgeVisible) ...[
                      const SizedBox(width: 8),
                      const GoldTickBadge(showLabel: true),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isApproved
                      ? 'Tutor status, availability, sessions, and earnings now live behind this Home entry point only.'
                      : 'Your tutor controls live here. Finish your application or review current status from this entry point.',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    signal(label: 'Status', value: tutor.statusLabel),
                    const SizedBox(width: 10),
                    signal(
                      label: 'Availability',
                      value: tutor.availabilityLabel,
                    ),
                    const SizedBox(width: 10),
                    signal(
                      label: isApproved ? 'Sessions' : 'Next step',
                      value: isApproved
                          ? '$sessionsCompleted done'
                          : 'Complete profile',
                    ),
                  ],
                ),
                if (isApproved) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      signal(
                        label: 'Learners helped',
                        value: '$learnersHelped',
                      ),
                      const SizedBox(width: 10),
                      signal(
                        label: 'Rating',
                        value: tutor.performance.ratingLabel,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C09E),
                      foregroundColor: const Color(0xFF0F142B),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => isApproved
                              ? const TutorStatsView()
                              : const TutorApplicationView(),
                        ),
                      );
                    },
                    child: Text(
                      isApproved
                          ? 'Open Tutor Desk'
                          : 'Continue Tutor Application',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white12),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FindTutorView(),
                        ),
                      );
                    },
                    child: const Text('Find Tutors As A Learner'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InstantTutorModeBottomNav extends StatelessWidget {
  const _InstantTutorModeBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFF0F142B),
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      onTap: onTap,
      selectedItemColor: const Color(0xFF00C09E),
      unselectedItemColor: Colors.white38,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
        BottomNavigationBarItem(
          icon: Icon(Icons.badge_outlined),
          label: 'Instant Tutor',
        ),
      ],
    );
  }
}
