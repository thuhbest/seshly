import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'billing_profile_service.dart';
import 'tutor_organization_service.dart';

class OrganizationSubscriptionException implements Exception {
  const OrganizationSubscriptionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'OrganizationSubscriptionException($code): $message';
}

class OrganizationSubscriptionService {
  OrganizationSubscriptionService()
    : _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  static const int monthlyPriceZar = 250;
  static const String productName = 'Organization Account';

  Future<void> activateSubscription({
    required User adminUser,
    required Map<String, dynamic> adminUserData,
    required TutorOrganizationAccount organization,
  }) async {
    final billingProfile = BillingProfileService.fromUserData(
      adminUserData,
      isAnonymousAuth: adminUser.isAnonymous,
    );
    if (billingProfile.isTemporary ||
        !billingProfile.isReady ||
        !billingProfile.hasDigits) {
      throw const OrganizationSubscriptionException(
        'missing_payment_method',
        'Set up a default card before activating the organization account plan.',
      );
    }

    if (organization.ownerUserId.trim().isEmpty) {
      throw const OrganizationSubscriptionException(
        'invalid_organization',
        'Organization billing owner is missing.',
      );
    }

    try {
      await _functions.httpsCallable('activateOrganizationSubscription').call(
        <String, dynamic>{'organizationId': organization.id},
      );
    } on FirebaseFunctionsException catch (error) {
      throw OrganizationSubscriptionException(
        error.code,
        error.message ?? 'Organization subscription activation failed.',
      );
    }
  }
}
