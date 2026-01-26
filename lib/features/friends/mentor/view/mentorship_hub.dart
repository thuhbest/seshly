import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/mentorship_service.dart';
import 'mentorship_admin_view.dart';
import 'mentorship_profile_sheet.dart';
import 'mentee_mentorship_view.dart';
import 'mentor_dashboard_view.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class MentorshipHub extends StatefulWidget {
  final void Function(String userId, String userName) onMessageUser;

  const MentorshipHub({super.key, required this.onMessageUser});

  @override
  State<MentorshipHub> createState() => _MentorshipHubState();
}

class _MentorshipHubState extends State<MentorshipHub> {
  final MentorshipService _service = MentorshipService();
  final Color cardColor = const Color(0xFF1E243A);

  @override
  Widget build(BuildContext context) {
    final currentUserId = _service.currentUserId;
    if (currentUserId == null) {
      return const Center(child: Text('Sign in to use mentorship.', style: TextStyle(color: Colors.white54)));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _service.watchProfile(currentUserId),
      builder: (context, profileSnap) {
        final profile = profileSnap.data?.data();
        final hasProfile = profile != null && profile.isNotEmpty;
        final safeProfile = profile ?? <String, dynamic>{};
        final role = (profile?['role'] ?? 'mentee').toString();
        final optIn = profile?['optIn'] == true;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final isAdmin = userData['isMentorshipAdmin'] == true;
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isAdmin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: PressableScale(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MentorshipAdminView()),
                        ),
                        borderRadius: BorderRadius.circular(10),
                        pressedScale: 0.96,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF00C09E).withValues(alpha: 0.35)),
                          ),
                          child: const Text("Admin insights", style: TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  if (!hasProfile)
                    _OnboardingCard(
                      onStart: () => _showProfileSheet(safeProfile, userData),
                    )
                  else ...[
                    if (!optIn)
                      _privacyBanner(
                        onTap: () => _showProfileSheet(safeProfile, userData),
                      ),
                    if (role == 'mentor')
                      MentorDashboardView(
                        onMessageUser: widget.onMessageUser,
                        service: _service,
                      )
                    else
                      MenteeMentorshipView(
                        onMessageUser: widget.onMessageUser,
                        service: _service,
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showProfileSheet(
    Map<String, dynamic> existing,
    Map<String, dynamic> userData,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => MentorshipProfileSheet(
        service: _service,
        existingProfile: existing,
        userData: userData,
      ),
    );
  }

  Widget _privacyBanner({required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFF00C09E), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Opt into privacy-safe analytics to unlock admin insights.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          PressableScale(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            pressedScale: 0.96,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00C09E).withValues(alpha: 0.35)),
              ),
              child: const Text('Enable', style: TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  final VoidCallback onStart;

  const _OnboardingCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Mentorship", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            "Create your mentorship profile to get matched with the right mentor or mentee.",
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: const Color(0xFF0F142B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Set up mentorship"),
            ),
          ),
        ],
      ),
    );
  }
}
