import 'package:flutter/material.dart';

import 'access_controller.dart';
import 'app_session_scope.dart';

enum TutorAccessSurface { application, desk, goldTick }

class TutorAccessDecision {
  const TutorAccessDecision({
    required this.allowed,
    required this.title,
    required this.description,
  });

  final bool allowed;
  final String title;
  final String description;
}

class TutorAccessPolicy {
  static TutorAccessDecision evaluate(
    AppSession session, {
    required TutorAccessSurface surface,
  }) {
    if (session.identity.isInstantTutor) {
      return const TutorAccessDecision(
        allowed: false,
        title: 'Tutor operations are locked in Instant Tutor Mode',
        description:
            'Instant Tutor Mode includes tutor discovery, tutor profiles, temporary card setup, and tutor booking only. Tutor applications, Tutor Desk controls, and Gold Tick management require a verified student tutor account.',
      );
    }

    switch (surface) {
      case TutorAccessSurface.application:
        return const TutorAccessDecision(
          allowed: true,
          title: '',
          description: '',
        );
      case TutorAccessSurface.desk:
        if (!session.tutor.hasApplied) {
          return const TutorAccessDecision(
            allowed: false,
            title: 'Apply as a tutor first',
            description:
                'Tutor Desk is only available after you create a tutor profile. Complete your tutor application first, then return here for availability, requests, ratings, and Gold Tick progress.',
          );
        }
        if (!session.tutor.isApproved) {
          return const TutorAccessDecision(
            allowed: false,
            title: 'Tutor Desk unlocks after approval',
            description:
                'Your tutor profile exists, but Tutor Desk controls only go live once the tutor status is approved or active.',
          );
        }
        return const TutorAccessDecision(
          allowed: true,
          title: '',
          description: '',
        );
      case TutorAccessSurface.goldTick:
        if (!session.tutor.isApproved) {
          return const TutorAccessDecision(
            allowed: false,
            title: 'Gold Tick is for approved tutors',
            description:
                'Gold Tick is a premium tutor trust product for approved tutors with a real quality track record. Finish tutor approval first, then build rating and qualifying-session history.',
          );
        }
        return const TutorAccessDecision(
          allowed: true,
          title: '',
          description: '',
        );
    }
  }

  static Future<bool> guard(
    BuildContext context, {
    required TutorAccessSurface surface,
  }) async {
    final decision = evaluate(
      AccessController.session(context),
      surface: surface,
    );
    if (decision.allowed) return true;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E243A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return TutorAccessGate(
          title: decision.title,
          description: decision.description,
          primaryLabel: 'Continue',
          onPrimaryPressed: () => Navigator.pop(sheetContext),
          showScaffold: false,
        );
      },
    );
    return false;
  }
}

class TutorAccessGate extends StatelessWidget {
  const TutorAccessGate({
    super.key,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.onPrimaryPressed,
    this.showScaffold = true,
  });

  final String title;
  final String description;
  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final bool showScaffold;

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Tutor Access',
                style: TextStyle(
                  color: Color(0xFF00C09E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (primaryLabel != null && onPrimaryPressed != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onPrimaryPressed,
                  child: Text(primaryLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!showScaffold) return content;

    return Scaffold(
      backgroundColor: const Color(0xFF0F142B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: content,
    );
  }
}
