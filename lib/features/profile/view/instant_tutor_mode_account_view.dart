import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:seshly/widgets/responsive.dart';

class InstantTutorModeAccountView extends StatelessWidget {
  const InstantTutorModeAccountView({super.key});

  static const Color _backgroundColor = Color(0xFF0F142B);
  static const Color _cardColor = Color(0xFF1E243A);
  static const Color _accentColor = Color(0xFF00C09E);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Text(
            'Instant Tutor Mode session not found.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: ResponsiveCenter(
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRestrictions(),
              const SizedBox(height: 18),
              _buildActions(context),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestrictions() {
    const items = [
      'Read the Home feed, but stay out of posting and academic interaction.',
      'Keep tutor discovery, tutor profiles, and booking fully open.',
      'Leave StudyVault, Sesh AI, Friends, and Calendar for verified student accounts.',
      'Use one temporary card scoped only to tutor booking and payment flow.',
    ];

    return _sectionCard(
      title: 'What Instant Tutor Mode includes',
      subtitle:
          'Browse the Home feed, move straight into tutor discovery and booking, then upgrade later for the full student experience.',
      child: Column(
        children: items
            .map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _cardColor.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: _accentColor,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    Future<void> switchToVerifiedStudentAccess() async {
      await FirebaseAuth.instance.signOut();
    }

    return _sectionCard(
      title: 'Upgrade path',
      subtitle: 'Full Seshly features require a verified student account.',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: switchToVerifiedStudentAccess,
              child: const Text('Create or sign in to a full account'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
