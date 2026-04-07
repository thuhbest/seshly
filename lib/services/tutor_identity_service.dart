import 'package:seshly/services/community_backend_service.dart';
import 'package:seshly/services/tutor_session_service.dart';
import 'package:seshly/services/gold_tick_service.dart';
import 'package:seshly/services/tutor_organization_service.dart';

enum TutorLifecycleStatus {
  none,
  submitted,
  underReview,
  approved,
  active,
  rejected,
  suspended,
}

enum TutorAvailabilityState { offline, accepting, afterCurrent }

class TutorOrganizationProfile {
  const TutorOrganizationProfile({
    required this.id,
    required this.tutorType,
    required this.name,
    required this.role,
    required this.website,
    required this.bio,
    required this.logoUrl,
    required this.ratingAverage10,
    required this.ratingCount,
    required this.memberTutorCount,
    required this.activeTutorCount,
    required this.subjects,
    required this.services,
    required this.verificationStatus,
    required this.isAdmin,
    required this.isActiveApproved,
  });

  final String? id;
  final String tutorType;
  final String name;
  final String role;
  final String website;
  final String bio;
  final String logoUrl;
  final double ratingAverage10;
  final int ratingCount;
  final int memberTutorCount;
  final int activeTutorCount;
  final List<String> subjects;
  final List<String> services;
  final String verificationStatus;
  final bool isAdmin;
  final bool isActiveApproved;

  bool get isLinkedOrganization =>
      id?.trim().isNotEmpty == true && name.trim().isNotEmpty;

  String get affiliationLabel {
    if (!isLinkedOrganization) return 'Independent tutor';
    return 'Member of $name';
  }

  String get subtitle {
    if (!isLinkedOrganization) return 'Independent tutor';
    if (role.trim().isEmpty) return affiliationLabel;
    return '$affiliationLabel • $role';
  }

  String get ratingLabel => ratingCount > 0
      ? '${ratingAverage10.toStringAsFixed(1)}/10'
      : 'New organization';
}

class TutorPerformanceSnapshot {
  const TutorPerformanceSnapshot({
    required this.minutesTutored,
    required this.learnersHelped,
    required this.sessionsCompleted,
    required this.qualifyingSessionCount,
    required this.ratingAverage,
    required this.ratingCount,
    required this.totalEarnings,
  });

  final int minutesTutored;
  final int learnersHelped;
  final int sessionsCompleted;
  final int qualifyingSessionCount;
  final double ratingAverage;
  final int ratingCount;
  final int totalEarnings;

  bool get hasRating => ratingAverage > 0 && ratingCount > 0;

  String get ratingLabel =>
      hasRating ? '${ratingAverage.toStringAsFixed(1)}/10' : 'New tutor';

  String get ratingCountLabel => ratingCount > 0 ? '($ratingCount)' : '';

  String get earningsLabel => 'R$totalEarnings';
}

class TutorIdentity {
  const TutorIdentity({
    this.id = '',
    this.displayName = '',
    this.profileImageUrl = '',
    required this.status,
    required this.availability,
    required this.requestsEnabled,
    required this.mainSubjects,
    required this.minorSubjects,
    required this.allSubjects,
    required this.targetAudience,
    required this.highestLevel,
    required this.organization,
    required this.performance,
    required this.pricing,
    required this.goldTick,
  });

  final String id;
  final String displayName;
  final String profileImageUrl;
  final TutorLifecycleStatus status;
  final TutorAvailabilityState availability;
  final bool requestsEnabled;
  final List<String> mainSubjects;
  final List<String> minorSubjects;
  final List<String> allSubjects;
  final String targetAudience;
  final String highestLevel;
  final TutorOrganizationProfile organization;
  final TutorPerformanceSnapshot performance;
  final TutorPricingBreakdown pricing;
  final GoldTickSnapshot goldTick;

  static const empty = TutorIdentity(
    status: TutorLifecycleStatus.none,
    availability: TutorAvailabilityState.offline,
    requestsEnabled: false,
    mainSubjects: <String>[],
    minorSubjects: <String>[],
    allSubjects: <String>[],
    targetAudience: 'Varsity Students',
    highestLevel: 'Not set',
    organization: TutorOrganizationProfile(
      id: null,
      tutorType: 'Individual',
      name: '',
      role: '',
      website: '',
      bio: '',
      logoUrl: '',
      ratingAverage10: 0,
      ratingCount: 0,
      memberTutorCount: 0,
      activeTutorCount: 0,
      subjects: <String>[],
      services: <String>[],
      verificationStatus: 'none',
      isAdmin: false,
      isActiveApproved: false,
    ),
    performance: TutorPerformanceSnapshot(
      minutesTutored: 0,
      learnersHelped: 0,
      sessionsCompleted: 0,
      qualifyingSessionCount: 0,
      ratingAverage: 0,
      ratingCount: 0,
      totalEarnings: 0,
    ),
    pricing: TutorPricingBreakdown(
      tutorRatePerMinute: 0,
      platformFeePerMinute: 0,
      totalRatePerMinute: 0,
    ),
    goldTick: GoldTickSnapshot(
      subscriptionStatus: GoldTickSubscriptionStatus.none,
      eligibilityStatus: GoldTickEligibilityStatus.ineligible,
      eligibilityPath: GoldTickEligibilityPath.none,
      eligibilityReason: 'Tutor quality progress is unavailable right now.',
      badgeVisible: false,
      rankingBoostEnabled: false,
      ratingAverage10: 0,
      ratingCount: 0,
      qualifyingSessionCount: 0,
      organizationEligible: false,
      organizationRatingAverage10: 0,
      organizationRatingCount: 0,
      memberQualificationStatus: '',
      currentPeriodStart: null,
      currentPeriodEnd: null,
      priceZar: GoldTickService.monthlyPriceZar,
      legacyQualificationEstimate: false,
    ),
  );

  bool get hasApplied => status != TutorLifecycleStatus.none;

  bool get isApproved =>
      status == TutorLifecycleStatus.approved ||
      status == TutorLifecycleStatus.active;

  bool get canOpenTutorDesk => hasApplied;

  bool get canReceiveRequests =>
      isApproved &&
      requestsEnabled &&
      availability == TutorAvailabilityState.accepting;

  String get statusLabel {
    switch (status) {
      case TutorLifecycleStatus.active:
        return 'ACTIVE';
      case TutorLifecycleStatus.approved:
        return 'APPROVED';
      case TutorLifecycleStatus.submitted:
        return 'SUBMITTED';
      case TutorLifecycleStatus.underReview:
        return 'UNDER REVIEW';
      case TutorLifecycleStatus.rejected:
        return 'REJECTED';
      case TutorLifecycleStatus.suspended:
        return 'SUSPENDED';
      case TutorLifecycleStatus.none:
        return 'NOT APPLIED';
    }
  }

  String get availabilityLabel {
    switch (availability) {
      case TutorAvailabilityState.accepting:
        return 'ACCEPTING';
      case TutorAvailabilityState.afterCurrent:
        return 'AFTER CURRENT';
      case TutorAvailabilityState.offline:
        return 'OFFLINE';
    }
  }

  String availabilityCopy({required bool isOnline}) {
    switch (availability) {
      case TutorAvailabilityState.accepting:
        return isOnline ? 'Online & accepting' : 'Accepting requests';
      case TutorAvailabilityState.afterCurrent:
        return 'Finishing current session';
      case TutorAvailabilityState.offline:
        return 'Offline';
    }
  }
}

class TutorIdentityService {
  static Future<List<TutorIdentity>> searchTutors({
    required String subject,
    double? maxPrice,
    List<String>? availability,
    double? minRating,
    int limit = 20,
  }) async {
    final normalizedSubject = subject.trim().toLowerCase();
    if (normalizedSubject.isEmpty) return const <TutorIdentity>[];

    final normalizedAvailability = (availability ?? const <String>[])
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    final items = await CommunityBackendService.instance.searchTutors(
      subject: normalizedSubject,
      maxPrice: maxPrice,
      availability: normalizedAvailability.toList(),
      minRating: minRating,
      limit: limit,
    );

    return items
        .map((entry) => fromSearchProfile(entry, documentId: '${entry['id'] ?? ''}'))
        .where((tutor) {
          if (maxPrice != null && tutor.pricing.totalRatePerMinute > maxPrice) {
            return false;
          }
          if (minRating != null &&
              tutor.performance.ratingAverage < minRating) {
            return false;
          }
          if (normalizedAvailability.isNotEmpty &&
              !normalizedAvailability.contains(
                _availabilityValue(tutor.availability),
              )) {
            return false;
          }
          return true;
        })
        .take(limit <= 0 ? 20 : limit)
        .toList();
  }

  static TutorIdentity fromUserData(
    Map<String, dynamic> data, {
    String userId = '',
  }) {
    final profile = data['tutorProfile'] as Map<String, dynamic>? ?? {};
    final stats = data['tutorStats'] as Map<String, dynamic>? ?? {};
    final organizationSummary = TutorOrganizationService.membershipFromUserData(
      data,
    );

    final mainSubjects = _readStringList(profile['mainSubjects']);
    final minorSubjects = _readStringList(profile['minorSubjects']);
    final rootSubjects = _readStringList(data['tutorSubjects']);
    final subjects = <String>{}
      ..addAll(mainSubjects)
      ..addAll(minorSubjects)
      ..addAll(rootSubjects);

    final rawStatus = (data['tutorApplicationStatus'] ??
            profile['tutorApplicationStatus'] ??
            data['tutorStatus'] ??
            profile['status'] ??
            '')
        .toString();
    final rawEligibility =
        (data['tutoringEligibilityStatus'] ??
                profile['tutoringEligibilityStatus'] ??
                '')
            .toString();
    final adminApproval =
        data['adminApproval'] == true || profile['adminApproval'] == true;
    final requestsEnabled = data['tutorRequestsEnabled'] == true;
    final rawAvailability =
        (data['tutorAvailability'] ??
                (requestsEnabled ? 'accepting' : 'offline'))
            .toString();

    return TutorIdentity(
      id: _firstNonEmptyText([userId, data['uid'], data['userId']]),
      displayName: _firstNonEmptyText([
        data['fullName'],
        data['displayName'],
      ], fallback: 'Tutor'),
      profileImageUrl: _firstNonEmptyText([
        data['profilePic'],
        data['photoURL'],
      ]),
      status: _statusFrom(
        rawStatus,
        rawEligibility: rawEligibility,
        adminApproval: adminApproval,
      ),
      availability: _availabilityFrom(rawAvailability),
      requestsEnabled: requestsEnabled,
      mainSubjects: mainSubjects,
      minorSubjects: minorSubjects,
      allSubjects: subjects.toList(),
      targetAudience: (profile['targetAudience'] ?? 'Varsity Students')
          .toString(),
      highestLevel: (profile['highestLevel'] ?? 'Not set').toString(),
      organization: TutorOrganizationProfile(
        id: organizationSummary.organizationId.isNotEmpty
            ? organizationSummary.organizationId
            : (profile['organizationId'] ??
                      TutorOrganizationService.deriveOrganizationId(
                        tutorType: (profile['tutorType'] ?? 'Individual')
                            .toString(),
                        organizationName: (profile['organizationName'] ?? '')
                            .toString(),
                        website: (profile['organizationWebsite'] ?? '')
                            .toString(),
                      ))
                  ?.toString(),
        tutorType: organizationSummary.hasOrganization
            ? 'Organization'
            : (profile['tutorType'] ?? 'Individual').toString(),
        name: organizationSummary.organizationName.isNotEmpty
            ? organizationSummary.organizationName
            : (profile['organizationName'] ?? '').toString(),
        role: organizationSummary.memberTitle.isNotEmpty
            ? organizationSummary.memberTitle
            : (profile['organizationRole'] ?? '').toString(),
        website: organizationSummary.organizationWebsite.isNotEmpty
            ? organizationSummary.organizationWebsite
            : (profile['organizationWebsite'] ?? '').toString(),
        bio: organizationSummary.organizationBio,
        logoUrl: organizationSummary.organizationLogoUrl,
        ratingAverage10: organizationSummary.organizationRatingAverage10,
        ratingCount: organizationSummary.organizationRatingCount,
        memberTutorCount: organizationSummary.memberTutorCount,
        activeTutorCount: organizationSummary.activeTutorCount,
        subjects: organizationSummary.organizationSubjects,
        services: organizationSummary.organizationServices,
        verificationStatus: organizationSummary.verificationStatus.value,
        isAdmin: organizationSummary.isAdmin,
        isActiveApproved: organizationSummary.isActiveApproved,
      ),
      performance: TutorPerformanceSnapshot(
        minutesTutored: (stats['minutesTutored'] as num?)?.toInt() ?? 0,
        learnersHelped: (stats['learnersHelped'] as num?)?.toInt() ?? 0,
        sessionsCompleted: (stats['sessionsCompleted'] as num?)?.toInt() ?? 0,
        qualifyingSessionCount:
            (stats['qualifyingSessionCount'] as num?)?.toInt() ??
            (stats['sessionsCompleted'] as num?)?.toInt() ??
            0,
        ratingAverage: (stats['ratingAvg'] as num?)?.toDouble() ?? 0,
        ratingCount: (stats['ratingCount'] as num?)?.toInt() ?? 0,
        totalEarnings: (stats['totalEarnings'] as num?)?.toInt() ?? 0,
      ),
      pricing: TutorSessionService.buildPricing(data),
      goldTick: GoldTickService.fromUserData(data),
    );
  }

  static bool canAppearInDiscovery(
    Map<String, dynamic> data, {
    String? subject,
  }) {
    final tutor = fromUserData(data);
    final bool isOnline = data['isOnline'] == true;
    if (!isOnline && !tutor.canReceiveRequests) return false;

    final normalizedSubject = subject?.trim().toLowerCase() ?? '';
    if (normalizedSubject.isEmpty) return tutor.isApproved;
    return tutor.allSubjects.any(
      (item) => item.toLowerCase() == normalizedSubject,
    );
  }

  static List<String> subjectsFrom(Map<String, dynamic> data) {
    return fromUserData(data).allSubjects;
  }

  static TutorIdentity fromSearchProfile(
    Map<String, dynamic> data, {
    String documentId = '',
  }) {
    final organizationId = _firstNonEmptyText([data['organizationId']]);
    final organizationName = _firstNonEmptyText([data['organizationName']]);
    final ratingAverage = _readDouble(data['ratingAverage']);
    final ratingCount = _readInt(data['ratingCount']);
    final sessionsCompleted = _readInt(data['completedSessions']);
    final totalMinutesTaught = _readInt(data['totalMinutesTaught']);
    final qualifyingSessionCount = _readInt(data['qualifyingSessionCount']) > 0
        ? _readInt(data['qualifyingSessionCount'])
        : sessionsCompleted;
    final tutorRatePerMinute = _readDouble(data['baseRatePerMinuteZar']);
    final totalRatePerMinute = _readDouble(data['studentRatePerMinuteZar']);
    final platformFeePerMinute = (totalRatePerMinute - tutorRatePerMinute)
        .clamp(0, double.infinity)
        .toDouble();
    final organizationRatingAverage10 = _readDouble(
      data['organizationRatingAverage10'],
    );
    final organizationRatingCount = _readInt(data['organizationRatingCount']);
    final goldTickQualified = data['goldTickQualified'] == true;
    final organizationVerified = data['organizationVerified'] == true;
    final organizationEligible =
        organizationVerified ||
        organizationRatingAverage10 >= GoldTickService.requiredRating;
    final individualEligible =
        ratingAverage >= GoldTickService.requiredRating &&
        sessionsCompleted >= GoldTickService.requiredQualifyingSessions;

    return TutorIdentity(
      id: _firstNonEmptyText([data['tutorId'], documentId]),
      displayName: _firstNonEmptyText([
        data['displayName'],
        data['fullName'],
      ], fallback: 'Tutor'),
      profileImageUrl: _firstNonEmptyText([data['profilePic']]),
      status: _statusFrom(
        (data['tutorApplicationStatus'] ??
                ((data['tutoringSearchVisible'] == true ||
                            data['isActive'] == true)
                        ? 'approved'
                        : ''))
            .toString(),
        rawEligibility: (data['tutoringEligibilityStatus'] ?? '').toString(),
        adminApproval:
            data['adminApproval'] == true ||
            data['tutoringSearchVisible'] == true ||
            data['isActive'] == true,
      ),
      availability: _availabilityFrom(
        (data['availability'] ?? 'offline').toString(),
      ),
      requestsEnabled:
          data['tutorRequestsEnabled'] == true ||
          (data['availability'] ?? '').toString() == 'accepting',
      mainSubjects: _readStringList(data['mainSubjects']),
      minorSubjects: _readStringList(data['minorSubjects']),
      allSubjects: _readStringList(data['subjects']),
      targetAudience: _firstNonEmptyText([
        data['targetAudience'],
      ], fallback: 'Varsity Students'),
      highestLevel: _firstNonEmptyText([
        data['highestLevel'],
      ], fallback: 'Not set'),
      organization: TutorOrganizationProfile(
        id: organizationId.isNotEmpty ? organizationId : null,
        tutorType: organizationName.isNotEmpty ? 'Organization' : 'Individual',
        name: organizationName,
        role: '',
        website: '',
        bio: '',
        logoUrl: '',
        ratingAverage10: organizationRatingAverage10,
        ratingCount: organizationRatingCount,
        memberTutorCount: _readInt(data['organizationMemberTutorCount']),
        activeTutorCount: _readInt(data['organizationActiveTutorCount']),
        subjects: _readStringList(data['organizationSubjects']),
        services: _readStringList(data['organizationServices']),
        verificationStatus: organizationVerified ? 'verified' : 'none',
        isAdmin: false,
        isActiveApproved: organizationVerified,
      ),
      performance: TutorPerformanceSnapshot(
        minutesTutored: totalMinutesTaught,
        learnersHelped: _readInt(data['learnersHelped']) > 0
            ? _readInt(data['learnersHelped'])
            : sessionsCompleted,
        sessionsCompleted: sessionsCompleted,
        qualifyingSessionCount: qualifyingSessionCount,
        ratingAverage: ratingAverage,
        ratingCount: ratingCount,
        totalEarnings: _readInt(data['totalEarningsZar']),
      ),
      goldTick: GoldTickSnapshot(
        subscriptionStatus: goldTickQualified
            ? GoldTickSubscriptionStatus.active
            : GoldTickSubscriptionStatus.none,
        eligibilityStatus:
            goldTickQualified || individualEligible || organizationEligible
            ? GoldTickEligibilityStatus.eligible
            : GoldTickEligibilityStatus.ineligible,
        eligibilityPath: organizationEligible
            ? GoldTickEligibilityPath.organization
            : (goldTickQualified || individualEligible)
            ? GoldTickEligibilityPath.individual
            : GoldTickEligibilityPath.none,
        eligibilityReason: goldTickQualified
            ? 'Gold Tick is active for this tutor in discovery.'
            : organizationEligible
            ? 'This tutor benefits from verified organization quality signals.'
            : individualEligible
            ? 'This tutor is on track for Gold Tick eligibility.'
            : 'Gold Tick unlocks after stronger rating and session history.',
        badgeVisible: goldTickQualified,
        rankingBoostEnabled: goldTickQualified,
        ratingAverage10: ratingAverage,
        ratingCount: ratingCount,
        qualifyingSessionCount: qualifyingSessionCount,
        organizationEligible: organizationEligible,
        organizationRatingAverage10: organizationRatingAverage10,
        organizationRatingCount: organizationRatingCount,
        memberQualificationStatus: organizationVerified
            ? 'organization_verified'
            : '',
        currentPeriodStart: null,
        currentPeriodEnd: null,
        priceZar: GoldTickService.monthlyPriceZar,
        legacyQualificationEstimate: true,
      ),
      pricing: TutorPricingBreakdown(
        tutorRatePerMinute: tutorRatePerMinute,
        platformFeePerMinute: platformFeePerMinute,
        totalRatePerMinute: totalRatePerMinute,
      ),
    );
  }

  static TutorLifecycleStatus _statusFrom(
    String raw, {
    String rawEligibility = '',
    bool adminApproval = false,
  }) {
    final normalizedEligibility = rawEligibility.toLowerCase();
    if (normalizedEligibility == 'blocked') {
      return TutorLifecycleStatus.suspended;
    }
    if (adminApproval && normalizedEligibility == 'eligible') {
      return TutorLifecycleStatus.approved;
    }
    switch (raw.toLowerCase()) {
      case 'submitted':
      case 'pending':
        return TutorLifecycleStatus.submitted;
      case 'under_review':
        return TutorLifecycleStatus.underReview;
      case 'active':
        return TutorLifecycleStatus.active;
      case 'approved':
        return TutorLifecycleStatus.approved;
      case 'rejected':
        return TutorLifecycleStatus.rejected;
      case 'suspended':
        return TutorLifecycleStatus.suspended;
      default:
        return TutorLifecycleStatus.none;
    }
  }

  static TutorAvailabilityState _availabilityFrom(String raw) {
    switch (raw.toLowerCase()) {
      case 'accepting':
        return TutorAvailabilityState.accepting;
      case 'after_current':
        return TutorAvailabilityState.afterCurrent;
      default:
        return TutorAvailabilityState.offline;
    }
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  static String _availabilityValue(TutorAvailabilityState availability) {
    switch (availability) {
      case TutorAvailabilityState.accepting:
        return 'accepting';
      case TutorAvailabilityState.afterCurrent:
        return 'after_current';
      case TutorAvailabilityState.offline:
        return 'offline';
    }
  }

  static double _readDouble(dynamic value) => (value as num?)?.toDouble() ?? 0;

  static int _readInt(dynamic value) => (value as num?)?.toInt() ?? 0;

  static String _firstNonEmptyText(
    List<dynamic> values, {
    String fallback = '',
  }) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }
}
