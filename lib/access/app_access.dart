import 'package:flutter/material.dart';

import 'app_identity.dart';

enum AppAccessTier { verifiedStudent, instantTutor }

enum AppCapability {
  viewHomeFeed,
  postQuestion,
  comment,
  reactHelpful,
  repostQuestion,
  viewStudyVault,
  viewNotifications,
  useSeshFocus,
  useSesh,
  accessFriends,
  accessCalendar,
  viewFullProfile,
  bookTutor,
  attachTemporaryCard,
}

class AppAccessProfile {
  AppAccessProfile._({
    required this.tier,
    required Set<AppCapability> capabilities,
  }) : capabilities = Set.unmodifiable(capabilities);

  factory AppAccessProfile.fromIdentity(AppIdentity identity) {
    return identity.isInstantTutor
        ? AppAccessProfile._(
            tier: AppAccessTier.instantTutor,
            capabilities: _instantTutorCapabilities,
          )
        : AppAccessProfile._(
            tier: AppAccessTier.verifiedStudent,
            capabilities: _verifiedStudentCapabilities,
          );
  }

  final AppAccessTier tier;
  final Set<AppCapability> capabilities;

  static final Set<AppCapability> _verifiedStudentCapabilities = {
    ...AppCapability.values,
  };

  static final Set<AppCapability> _instantTutorCapabilities = {
    AppCapability.viewHomeFeed,
    AppCapability.bookTutor,
    AppCapability.attachTemporaryCard,
  };

  bool get isInstantTutor => tier == AppAccessTier.instantTutor;

  bool get isVerifiedStudent => tier == AppAccessTier.verifiedStudent;

  bool can(AppCapability capability) => capabilities.contains(capability);

  String get badgeLabel =>
      isInstantTutor ? 'Instant Tutor Mode' : 'Full Account';
}

String accessTitleFor(AppCapability capability) {
  switch (capability) {
    case AppCapability.postQuestion:
      return 'Posting is locked in Instant Tutor Mode';
    case AppCapability.comment:
      return 'Answering is locked in Instant Tutor Mode';
    case AppCapability.reactHelpful:
      return 'Reactions are locked in Instant Tutor Mode';
    case AppCapability.repostQuestion:
      return 'Reposts are locked in Instant Tutor Mode';
    case AppCapability.viewStudyVault:
      return 'StudyVault requires a full account';
    case AppCapability.viewNotifications:
      return 'Notifications require a full account';
    case AppCapability.useSeshFocus:
      return 'SeshFocus requires a full account';
    case AppCapability.useSesh:
      return 'Sesh requires a full account';
    case AppCapability.accessFriends:
      return 'Community features require a full account';
    case AppCapability.accessCalendar:
      return 'Calendar requires a full account';
    case AppCapability.viewFullProfile:
      return 'Profiles are restricted in Instant Tutor Mode';
    case AppCapability.bookTutor:
      return 'Tutor booking is available in Instant Tutor Mode';
    case AppCapability.attachTemporaryCard:
      return 'Temporary card linking is available in Instant Tutor Mode';
    case AppCapability.viewHomeFeed:
      return 'Home feed is available in Instant Tutor Mode';
  }
}

String accessDescriptionFor(AppCapability capability) {
  switch (capability) {
    case AppCapability.postQuestion:
    case AppCapability.comment:
    case AppCapability.reactHelpful:
    case AppCapability.repostQuestion:
      return 'Instant Tutor Mode is read-only on the academic feed. Sign in to a full account to post, answer, react, or contribute.';
    case AppCapability.viewStudyVault:
      return 'Sign in to a full account to open StudyVault, unlock resources, and use uploader tools.';
    case AppCapability.viewNotifications:
      return 'Notifications stay tied to signed-in accounts and are not exposed in Instant Tutor Mode.';
    case AppCapability.useSeshFocus:
      return 'SeshFocus stays inside the full-account productivity flow.';
    case AppCapability.useSesh:
      return 'Sesh AI, Archive, and the wider Sesh workspace require a full account.';
    case AppCapability.accessFriends:
      return 'Friends, mentorship, leadership, and messaging require a full account.';
    case AppCapability.accessCalendar:
      return 'Calendar planning requires a full account. Instant Tutor Mode still supports tutor discovery and booking.';
    case AppCapability.viewFullProfile:
      return 'Instant Tutor Mode keeps tutor discovery and booking open, but full profiles stay locked.';
    case AppCapability.bookTutor:
      return 'Instant Tutor Mode already supports tutor discovery and booking.';
    case AppCapability.attachTemporaryCard:
      return 'Instant Tutor Mode already supports temporary card linking for tutor booking.';
    case AppCapability.viewHomeFeed:
      return 'Instant Tutor Mode already supports read-only Home feed browsing.';
  }
}

Future<void> showAccessRestrictionSheet(
  BuildContext context, {
  required AppCapability capability,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E243A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
                  'Instant Tutor Mode',
                  style: TextStyle(
                    color: Color(0xFF00C09E),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                accessTitleFor(capability),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                accessDescriptionFor(capability),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Available here: Home feed, tutor discovery, tutor booking, and temporary card linking.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Go Back'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
