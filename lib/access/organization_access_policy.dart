import 'package:flutter/material.dart';

import 'app_session_scope.dart';

enum OrganizationAccessSurface { hub, admin }

class OrganizationAccessDecision {
  const OrganizationAccessDecision({
    required this.allowed,
    required this.title,
    required this.description,
  });

  final bool allowed;
  final String title;
  final String description;
}

class OrganizationAccessPolicy {
  static OrganizationAccessDecision evaluate(
    AppSession session, {
    required OrganizationAccessSurface surface,
  }) {
    if (session.identity.isInstantTutor) {
      return const OrganizationAccessDecision(
        allowed: false,
        title: 'Organization accounts are locked in Instant Tutor Mode',
        description:
            'Instant Tutor Mode supports tutor discovery and tutor booking only. Organization onboarding and member management require a verified tutor account.',
      );
    }

    if (!session.tutor.isApproved) {
      return const OrganizationAccessDecision(
        allowed: false,
        title: 'Organization accounts unlock for approved tutors',
        description:
            'Finish tutor approval first. Organization creation, joining, and member operations sit inside the tutor system and depend on an approved tutor profile.',
      );
    }

    if (surface == OrganizationAccessSurface.admin &&
        !session.organization.isAdmin) {
      return const OrganizationAccessDecision(
        allowed: false,
        title: 'Admin access required',
        description:
            'This organization action is reserved for the owner or an organization admin. Members can still view the organization profile and roster.',
      );
    }

    return const OrganizationAccessDecision(
      allowed: true,
      title: '',
      description: '',
    );
  }

  static Future<bool> guard(
    BuildContext context, {
    required OrganizationAccessSurface surface,
  }) async {
    final decision = evaluate(AppSessionScope.of(context), surface: surface);
    if (decision.allowed) return true;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E243A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Organization Accounts',
                    style: TextStyle(
                      color: Color(0xFF00C09E),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  decision.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  decision.description,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return false;
  }
}
