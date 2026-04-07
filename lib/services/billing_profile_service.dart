import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BillingProfile {
  const BillingProfile({
    required this.isReady,
    required this.isTemporary,
    required this.setupStatus,
    required this.provider,
    required this.paymentMethodId,
    required this.registrationId,
    required this.providerReference,
    required this.authorizationCode,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.holder,
  });

  final bool isReady;
  final bool isTemporary;
  final String setupStatus;
  final String provider;
  final String paymentMethodId;
  final String registrationId;
  final String providerReference;
  final String authorizationCode;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final String holder;

  bool get hasDigits => last4.trim().isNotEmpty;
  bool get hasProviderReference =>
      registrationId.trim().isNotEmpty && providerReference.trim().isNotEmpty;
  bool get canAuthorizeTutoring => isReady && hasDigits && hasProviderReference;

  String get summary => '$brand •••• $last4';

  String get title =>
      isTemporary ? 'Temporary tutor-booking card' : 'Default payment method';

  String get emptyHeadline =>
      isTemporary ? 'No temporary card yet' : 'No default card yet';

  String get manageLabel => isTemporary
      ? (isReady ? 'Replace temporary card' : 'Link temporary card')
      : (isReady ? 'Replace card' : 'Add card');

  String get paymentProfileType =>
      isTemporary ? 'temporary_instant_tutor_card' : 'saved_student_card';

  String get paymentMethodSummary => hasDigits ? summary : brand;
}

class BillingProfileService {
  static BillingProfile fromUserData(
    Map<String, dynamic> data, {
    bool? isAnonymousAuth,
  }) {
    final bool isInstantTutorMode = isInstantTutorModeUser(
      data,
      isAnonymousAuth: isAnonymousAuth,
    );
    if (isInstantTutorMode) {
      final String status = (data['temporaryPaymentSetupStatus'] ?? 'missing')
          .toString();
      return BillingProfile(
        isReady: status == 'ready',
        isTemporary: true,
        setupStatus: status,
        provider: (data['temporaryPaymentProvider'] ?? 'Seshly Pay').toString(),
        paymentMethodId: (data['temporaryPaymentMethodId'] ?? '').toString(),
        registrationId: (data['temporaryPaymentRegistrationId'] ?? '')
            .toString(),
        providerReference: (data['temporaryPaymentProviderReference'] ?? '')
            .toString(),
        authorizationCode: (data['temporaryPaymentAuthorizationCode'] ?? '')
            .toString(),
        brand: (data['temporaryCardBrand'] ?? 'Card').toString(),
        last4: (data['temporaryCardLast4'] ?? '').toString(),
        expMonth: (data['temporaryCardExpMonth'] as num?)?.toInt() ?? 0,
        expYear: (data['temporaryCardExpYear'] as num?)?.toInt() ?? 0,
        holder: (data['temporaryCardHolder'] ?? 'Instant Tutor Learner')
            .toString(),
      );
    }

    final String status = (data['billingSetupStatus'] ?? 'missing').toString();
    return BillingProfile(
      isReady: status == 'ready',
      isTemporary: false,
      setupStatus: status,
      provider: (data['billingProvider'] ?? 'Seshly Pay').toString(),
      paymentMethodId: (data['billingDefaultPaymentMethodId'] ?? '').toString(),
      registrationId: (data['billingRegistrationId'] ?? '').toString(),
      providerReference: (data['billingProviderReference'] ?? '').toString(),
      authorizationCode: (data['billingAuthorizationCode'] ?? '').toString(),
      brand: (data['billingCardBrand'] ?? 'Card').toString(),
      last4: (data['billingCardLast4'] ?? '').toString(),
      expMonth: (data['billingCardExpMonth'] as num?)?.toInt() ?? 0,
      expYear: (data['billingCardExpYear'] as num?)?.toInt() ?? 0,
      holder: (data['billingCardHolder'] ?? '').toString(),
    );
  }

  static bool isInstantTutorModeUser(
    Map<String, dynamic> data, {
    bool? isAnonymousAuth,
  }) {
    if (isAnonymousAuth != null) {
      return isAnonymousAuth;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      return currentUser.isAnonymous;
    }

    final String accessTier = (data['accessTier'] ?? '')
        .toString()
        .toLowerCase();
    final String accountType = (data['accountType'] ?? '')
        .toString()
        .toLowerCase();
    final String accessMode = (data['accessMode'] ?? '')
        .toString()
        .toLowerCase();
    return accessTier == 'instant_tutor' ||
        accountType == 'instant_tutor' ||
        accessMode == 'instanttutor' ||
        data['instantTutorAccess'] == true;
  }

  static String paymentMethodCollectionName({required bool isTemporary}) {
    return isTemporary ? 'temporary_payment_methods' : 'payment_methods';
  }

  static Map<String, dynamic> buildCardFields({
    required bool isTemporary,
    required String brand,
    required String holder,
    required String last4,
    required int expMonth,
    required int expYear,
    required String paymentMethodId,
  }) {
    if (isTemporary) {
      return {
        'temporaryPaymentSetupStatus': 'ready',
        'temporaryPaymentProvider': 'Seshly Pay',
        'temporaryPaymentMethodId': paymentMethodId,
        'temporaryCardBrand': brand,
        'temporaryCardLast4': last4,
        'temporaryCardExpMonth': expMonth,
        'temporaryCardExpYear': expYear,
        'temporaryCardHolder': holder,
        'temporaryPaymentScope': 'tutor_booking_only',
        'temporaryPaymentUpdatedAt': FieldValue.serverTimestamp(),
      };
    }

    return {
      'billingSetupStatus': 'ready',
      'billingProvider': 'Seshly Pay',
      'billingDefaultPaymentMethodId': paymentMethodId,
      'billingCardBrand': brand,
      'billingCardLast4': last4,
      'billingCardExpMonth': expMonth,
      'billingCardExpYear': expYear,
      'billingCardHolder': holder,
      'billingAuthorizationMode': 'per_session',
      'billingUpdatedAt': FieldValue.serverTimestamp(),
    };
  }
}
