import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'billing_profile_service.dart';

enum GoldTickSubscriptionStatus {
  none,
  inactive,
  pendingActivation,
  active,
  suspendedIneligible,
  expired,
}

enum GoldTickEligibilityStatus { eligible, ineligible, atRisk }

enum GoldTickEligibilityPath { none, individual, organization }

class GoldTickSnapshot {
  const GoldTickSnapshot({
    required this.subscriptionStatus,
    required this.eligibilityStatus,
    required this.eligibilityPath,
    required this.eligibilityReason,
    required this.badgeVisible,
    required this.rankingBoostEnabled,
    required this.ratingAverage10,
    required this.ratingCount,
    required this.qualifyingSessionCount,
    required this.organizationEligible,
    required this.organizationRatingAverage10,
    required this.organizationRatingCount,
    required this.memberQualificationStatus,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.priceZar,
    required this.legacyQualificationEstimate,
  });

  final GoldTickSubscriptionStatus subscriptionStatus;
  final GoldTickEligibilityStatus eligibilityStatus;
  final GoldTickEligibilityPath eligibilityPath;
  final String eligibilityReason;
  final bool badgeVisible;
  final bool rankingBoostEnabled;
  final double ratingAverage10;
  final int ratingCount;
  final int qualifyingSessionCount;
  final bool organizationEligible;
  final double organizationRatingAverage10;
  final int organizationRatingCount;
  final String memberQualificationStatus;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final int priceZar;
  final bool legacyQualificationEstimate;

  bool get isEligible =>
      eligibilityStatus == GoldTickEligibilityStatus.eligible;

  bool get isActive => subscriptionStatus == GoldTickSubscriptionStatus.active;

  bool get canActivate => isEligible && !isActive;

  String get subscriptionLabel {
    switch (subscriptionStatus) {
      case GoldTickSubscriptionStatus.active:
        return 'Active';
      case GoldTickSubscriptionStatus.pendingActivation:
        return 'Pending activation';
      case GoldTickSubscriptionStatus.suspendedIneligible:
        return 'Suspended';
      case GoldTickSubscriptionStatus.expired:
        return 'Expired';
      case GoldTickSubscriptionStatus.inactive:
        return 'Inactive';
      case GoldTickSubscriptionStatus.none:
        return 'Not subscribed';
    }
  }

  String get eligibilityLabel {
    switch (eligibilityStatus) {
      case GoldTickEligibilityStatus.eligible:
        return 'Eligible';
      case GoldTickEligibilityStatus.atRisk:
        return 'At risk';
      case GoldTickEligibilityStatus.ineligible:
        return 'Not eligible';
    }
  }

  String get pathLabel {
    switch (eligibilityPath) {
      case GoldTickEligibilityPath.individual:
        return 'Individual quality path';
      case GoldTickEligibilityPath.organization:
        return 'Organization quality path';
      case GoldTickEligibilityPath.none:
        return 'No qualifying path yet';
    }
  }

  String get ratingLabel => ratingCount > 0
      ? '${ratingAverage10.toStringAsFixed(1)}/10'
      : 'New tutor';

  String get ratingCountLabel =>
      ratingCount > 0 ? '$ratingCount ratings' : 'No ratings yet';

  double get ratingProgress =>
      (ratingAverage10 / GoldTickService.requiredRating).clamp(0, 1);

  double get sessionProgress =>
      (qualifyingSessionCount / GoldTickService.requiredQualifyingSessions)
          .clamp(0, 1);

  String get qualifyingSessionLabel =>
      '$qualifyingSessionCount/${GoldTickService.requiredQualifyingSessions}+';

  bool get isWithinPaidPeriod =>
      currentPeriodEnd == null || currentPeriodEnd!.isAfter(DateTime.now());

  String get periodLabel {
    if (currentPeriodEnd == null) return 'Monthly';
    final end = currentPeriodEnd!;
    return '${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}/${end.year}';
  }
}

class GoldTickException implements Exception {
  const GoldTickException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'GoldTickException($code): $message';
}

class GoldTickService {
  GoldTickService()
    : _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  static const int monthlyPriceZar = 30;
  static const double requiredRating = 8;
  static const int requiredQualifyingSessions = 31;

  static GoldTickSnapshot fromUserData(Map<String, dynamic> data) {
    final gold = data['goldTick'] as Map<String, dynamic>? ?? {};
    final tutorStats = data['tutorStats'] as Map<String, dynamic>? ?? {};
    final bool legacyEstimate =
        gold['legacyQualificationEstimate'] == true ||
        !tutorStats.containsKey('qualifyingSessionCount');

    final int qualifyingSessions =
        (gold['qualifyingSessionCount'] as num?)?.toInt() ??
        (tutorStats['qualifyingSessionCount'] as num?)?.toInt() ??
        (legacyEstimate
            ? (tutorStats['sessionsCompleted'] as num?)?.toInt() ?? 0
            : 0);
    final double ratingAverage10 =
        (gold['ratingAverage10'] as num?)?.toDouble() ??
        (tutorStats['ratingAvg'] as num?)?.toDouble() ??
        0;
    final int ratingCount =
        (gold['ratingCount'] as num?)?.toInt() ??
        (tutorStats['ratingCount'] as num?)?.toInt() ??
        0;
    final double organizationRatingAverage10 =
        (gold['organizationRatingAverage10'] as num?)?.toDouble() ?? 0;
    final int organizationRatingCount =
        (gold['organizationRatingCount'] as num?)?.toInt() ?? 0;
    final bool organizationEligible =
        gold['organizationEligible'] == true ||
        organizationRatingAverage10 > requiredRating;

    final bool individualEligible =
        ratingAverage10 > requiredRating && qualifyingSessions > 30;
    final bool organizationPathEligible =
        organizationEligible &&
        (gold['memberQualificationStatus'] ?? '').toString() ==
            'auto_qualified';

    final eligibilityPath = _pathFrom(
      (gold['eligibilityPath'] ?? '').toString(),
      individualEligible: individualEligible,
      organizationEligible: organizationPathEligible,
    );
    final eligibilityStatus = _eligibilityFrom(
      (gold['eligibilityStatus'] ?? '').toString(),
      eligible: individualEligible || organizationPathEligible,
    );
    final currentPeriodStart = _readDate(gold['currentPeriodStart']);
    final currentPeriodEnd = _readDate(gold['currentPeriodEnd']);
    final rawStatus = (gold['subscriptionStatus'] ?? '').toString();
    final subscriptionStatus = _subscriptionFrom(
      rawStatus,
      currentPeriodEnd: currentPeriodEnd,
      isEligible: eligibilityStatus == GoldTickEligibilityStatus.eligible,
    );

    final bool isActive =
        subscriptionStatus == GoldTickSubscriptionStatus.active;
    final bool activeBadge =
        (gold['badgeVisible'] == true || gold['rankingBoostEnabled'] == true)
        ? isActive
        : (isActive && eligibilityStatus == GoldTickEligibilityStatus.eligible);

    return GoldTickSnapshot(
      subscriptionStatus: subscriptionStatus,
      eligibilityStatus: eligibilityStatus,
      eligibilityPath: eligibilityPath,
      eligibilityReason:
          (gold['eligibilityReason'] ??
                  _fallbackReason(
                    individualEligible: individualEligible,
                    organizationEligible: organizationPathEligible,
                    ratingAverage10: ratingAverage10,
                    qualifyingSessions: qualifyingSessions,
                    organizationRatingAverage10: organizationRatingAverage10,
                  ))
              .toString(),
      badgeVisible: activeBadge,
      rankingBoostEnabled: activeBadge,
      ratingAverage10: ratingAverage10,
      ratingCount: ratingCount,
      qualifyingSessionCount: qualifyingSessions,
      organizationEligible: organizationEligible,
      organizationRatingAverage10: organizationRatingAverage10,
      organizationRatingCount: organizationRatingCount,
      memberQualificationStatus: (gold['memberQualificationStatus'] ?? '')
          .toString(),
      currentPeriodStart: currentPeriodStart,
      currentPeriodEnd: currentPeriodEnd,
      priceZar: (gold['priceZar'] as num?)?.toInt() ?? monthlyPriceZar,
      legacyQualificationEstimate: legacyEstimate,
    );
  }

  Future<void> activateSubscription({
    required User user,
    required Map<String, dynamic> userData,
  }) async {
    final goldTick = GoldTickService.fromUserData(userData);
    if (!goldTick.isEligible) {
      throw GoldTickException('not_eligible', goldTick.eligibilityReason);
    }

    final billingProfile = BillingProfileService.fromUserData(
      userData,
      isAnonymousAuth: user.isAnonymous,
    );
    if (billingProfile.isTemporary ||
        !billingProfile.canAuthorizeTutoring ||
        !billingProfile.hasDigits) {
      throw const GoldTickException(
        'missing_payment_method',
        'Set up a verified default card before activating Gold Tick.',
      );
    }

    try {
      await _functions
          .httpsCallable('activateGoldTickSubscription')
          .call(<String, dynamic>{});
    } on FirebaseFunctionsException catch (error) {
      throw GoldTickException(
        error.code,
        error.message ?? 'Gold Tick activation failed.',
      );
    }
  }

  static GoldTickSubscriptionStatus _subscriptionFrom(
    String raw, {
    required DateTime? currentPeriodEnd,
    required bool isEligible,
  }) {
    final normalized = raw.toLowerCase();
    if (normalized == 'active') {
      if (currentPeriodEnd != null &&
          currentPeriodEnd.isBefore(DateTime.now())) {
        return GoldTickSubscriptionStatus.expired;
      }
      return isEligible
          ? GoldTickSubscriptionStatus.active
          : GoldTickSubscriptionStatus.suspendedIneligible;
    }
    switch (normalized) {
      case 'pending_activation':
        return GoldTickSubscriptionStatus.pendingActivation;
      case 'inactive':
        return GoldTickSubscriptionStatus.inactive;
      case 'suspended_ineligible':
        return GoldTickSubscriptionStatus.suspendedIneligible;
      case 'expired':
        return GoldTickSubscriptionStatus.expired;
      default:
        return GoldTickSubscriptionStatus.none;
    }
  }

  static GoldTickEligibilityStatus _eligibilityFrom(
    String raw, {
    required bool eligible,
  }) {
    switch (raw.toLowerCase()) {
      case 'eligible':
        return GoldTickEligibilityStatus.eligible;
      case 'at_risk':
        return GoldTickEligibilityStatus.atRisk;
      case 'ineligible':
        return GoldTickEligibilityStatus.ineligible;
      default:
        return eligible
            ? GoldTickEligibilityStatus.eligible
            : GoldTickEligibilityStatus.ineligible;
    }
  }

  static GoldTickEligibilityPath _pathFrom(
    String raw, {
    required bool individualEligible,
    required bool organizationEligible,
  }) {
    switch (raw.toLowerCase()) {
      case 'individual':
        return GoldTickEligibilityPath.individual;
      case 'organization':
        return GoldTickEligibilityPath.organization;
      default:
        if (individualEligible) return GoldTickEligibilityPath.individual;
        if (organizationEligible) return GoldTickEligibilityPath.organization;
        return GoldTickEligibilityPath.none;
    }
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  static String _fallbackReason({
    required bool individualEligible,
    required bool organizationEligible,
    required double ratingAverage10,
    required int qualifyingSessions,
    required double organizationRatingAverage10,
  }) {
    if (individualEligible) {
      return 'Eligible through individual quality performance.';
    }
    if (organizationEligible) {
      return 'Eligible through organization quality status.';
    }
    if (ratingAverage10 <= requiredRating) {
      return 'Raise your tutor rating above 8/10 to qualify.';
    }
    if (qualifyingSessions <= 30) {
      return 'Complete more than 30 qualifying tutoring sessions to qualify.';
    }
    if (organizationRatingAverage10 > 0 &&
        organizationRatingAverage10 <= requiredRating) {
      return 'Your organization needs a rating above 8/10 before members can qualify through the org path.';
    }
    return 'Gold Tick remains locked until your quality track record is strong enough.';
  }
}
