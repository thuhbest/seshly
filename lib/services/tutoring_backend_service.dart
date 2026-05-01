import 'package:cloud_functions/cloud_functions.dart';

class TutoringBackendException implements Exception {
  const TutoringBackendException(
    this.code,
    this.message, {
    this.errorCode,
    this.details = const <String, dynamic>{},
  });

  final String code;
  final String message;
  final String? errorCode;
  final Map<String, dynamic> details;

  @override
  String toString() =>
      'TutoringBackendException(${errorCode ?? code}): $message';
}

class TutoringBackendService {
  TutoringBackendService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> createTutoringBooking(
    Map<String, dynamic> data,
  ) => _call('createTutoringBooking', data);

  Future<Map<String, dynamic>> createGuestTutoringCustomer({
    String firstName = '',
    String email = '',
    String phone = '',
  }) => _call('createGuestTutoringCustomer', {
    'firstName': firstName,
    'email': email,
    'phone': phone,
  });

  Future<Map<String, dynamic>> updateGuestTutoringCustomer({
    String? firstName,
    String? email,
    String? phone,
  }) => _call('updateGuestTutoringCustomer', {
    if (firstName != null) 'firstName': firstName,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
  });

  Future<Map<String, dynamic>> submitTutorApplication(
    Map<String, dynamic> data,
  ) => _call('submitTutorApplication', data);

  Future<Map<String, dynamic>> reviewTutorApplication({
    required String tutorId,
  }) => _call('reviewTutorApplication', {'tutorId': tutorId});

  Future<Map<String, dynamic>> approveTutorApplication({
    required String tutorId,
  }) => _call('approveTutorApplication', {'tutorId': tutorId});

  Future<Map<String, dynamic>> rejectTutorApplication({
    required String tutorId,
    required String rejectionReason,
  }) => _call('rejectTutorApplication', {
    'tutorId': tutorId,
    'rejectionReason': rejectionReason,
  });

  Future<Map<String, dynamic>> suspendTutor({
    required String tutorId,
    required String suspensionReason,
  }) => _call('suspendTutor', {
    'tutorId': tutorId,
    'suspensionReason': suspensionReason,
  });

  Future<Map<String, dynamic>> restoreTutor({
    required String tutorId,
  }) => _call('restoreTutor', {'tutorId': tutorId});

  Future<Map<String, dynamic>> setTutorPayoutReadiness({
    required String tutorId,
    required String payoutOnboardingStatus,
  }) => _call('setTutorPayoutReadiness', {
    'tutorId': tutorId,
    'payoutOnboardingStatus': payoutOnboardingStatus,
  });

  Future<Map<String, dynamic>> getSupportedBanksForTutorPayout() =>
      _call('getSupportedBanksForTutorPayout', const <String, dynamic>{});

  Future<Map<String, dynamic>> submitTutorPayoutDetails({
    required String bankCode,
    required String accountNumber,
    required String accountHolderName,
  }) => _call('submitTutorPayoutDetails', {
    'bankCode': bankCode,
    'accountNumber': accountNumber,
    'accountHolderName': accountHolderName,
  });

  Future<Map<String, dynamic>> verifyTutorPayoutProfile({
    String? payoutProfileId,
    required String accountNumber,
  }) => _call('verifyTutorPayoutProfile', {
    if (payoutProfileId != null && payoutProfileId.trim().isNotEmpty)
      'payoutProfileId': payoutProfileId,
    'accountNumber': accountNumber,
  });

  Future<Map<String, dynamic>> runTutorApprovalBackfill({
    bool dryRun = false,
    String? tutorId,
  }) => _call('runTutorApprovalBackfill', {
    'dryRun': dryRun,
    if (tutorId != null && tutorId.trim().isNotEmpty) 'tutorId': tutorId,
  });

  Future<Map<String, dynamic>> refreshTutorPayoutDashboardAggregates({
    String? weekKey,
  }) => _call('refreshTutorPayoutDashboardAggregates', {
    if (weekKey != null && weekKey.trim().isNotEmpty) 'weekKey': weekKey,
  });

  Future<Map<String, dynamic>> listTutorsDueForMondayPayout({
    String? weekKey,
    int limit = 50,
  }) => _call('listTutorsDueForMondayPayout', {
    if (weekKey != null && weekKey.trim().isNotEmpty) 'weekKey': weekKey,
    'limit': limit,
  });

  Future<Map<String, dynamic>> getTutorPayoutTotalsByWeek({
    int limit = 8,
  }) => _call('getTutorPayoutTotalsByWeek', {
    'limit': limit,
  });

  Future<Map<String, dynamic>> listBlockedTutorPayoutProfiles({
    int limit = 50,
  }) => _call('listBlockedTutorPayoutProfiles', {
    'limit': limit,
  });

  Future<Map<String, dynamic>> listFailedTutorPayoutAttempts({
    String? weekKey,
    int limit = 50,
  }) => _call('listFailedTutorPayoutAttempts', {
    if (weekKey != null && weekKey.trim().isNotEmpty) 'weekKey': weekKey,
    'limit': limit,
  });

  Future<Map<String, dynamic>> listDisputedTutorPayables({
    String? weekKey,
    int limit = 50,
  }) => _call('listDisputedTutorPayables', {
    if (weekKey != null && weekKey.trim().isNotEmpty) 'weekKey': weekKey,
    'limit': limit,
  });

  Future<Map<String, dynamic>> getTutorPayoutHistoryByTutor({
    required String tutorId,
    int limit = 50,
  }) => _call('getTutorPayoutHistoryByTutor', {
    'tutorId': tutorId,
    'limit': limit,
  });

  Future<Map<String, dynamic>> exportTutorPayoutData({
    String dataset = 'payout_records',
    String? weekKey,
    String? tutorId,
    int limit = 100,
  }) => _call('exportTutorPayoutData', {
    'dataset': dataset,
    if (weekKey != null && weekKey.trim().isNotEmpty) 'weekKey': weekKey,
    if (tutorId != null && tutorId.trim().isNotEmpty) 'tutorId': tutorId,
    'limit': limit,
  });

  Future<Map<String, dynamic>> getTutorPayoutDashboard() =>
      _call('getTutorPayoutDashboard', const <String, dynamic>{});

  Future<Map<String, dynamic>> listTutorPayoutHistory({
    int limit = 20,
  }) => _call('listTutorPayoutHistory', {
    'limit': limit,
  });

  Future<Map<String, dynamic>> startTutoringPreauth({
    required String bookingId,
  }) => _call('startTutoringPreauth', {'bookingId': bookingId});

  Future<Map<String, dynamic>> respondToTutoringBooking({
    required String bookingId,
    required String action,
    String? scheduledAtIso,
  }) => _call('respondToTutoringBooking', {
    'bookingId': bookingId,
    'action': action,
    if (scheduledAtIso != null) 'scheduledAt': scheduledAtIso,
  });

  Future<Map<String, dynamic>> submitTutoringRating({
    required String bookingId,
    required int stars,
    String reviewText = '',
  }) => _call('submitTutoringRating', {
    'bookingId': bookingId,
    'stars': stars,
    'reviewText': reviewText,
  });

  Future<Map<String, dynamic>> setupTutoringPaymentMethod({
    required bool isTemporary,
    required String brand,
    required String holder,
    required String last4,
    required int expMonth,
    required int expYear,
  }) => _call('setupTutoringPaymentMethod', {
    'isTemporary': isTemporary,
    'brand': brand,
    'holder': holder,
    'last4': last4,
    'expMonth': expMonth,
    'expYear': expYear,
  });

  Future<Map<String, dynamic>> saveMockTutoringPaymentMethod({
    required bool isTemporary,
    required String brand,
    required String holder,
    required String last4,
    required int expMonth,
    required int expYear,
  }) => _call('saveMockTutoringPaymentMethod', {
    'isTemporary': isTemporary,
    'brand': brand,
    'holder': holder,
    'last4': last4,
    'expMonth': expMonth,
    'expYear': expYear,
  });

  Future<Map<String, dynamic>> startSession({
    required String bookingId,
  }) => _call('startSession', {'bookingId': bookingId});

  Future<Map<String, dynamic>> endSession({
    required String sessionId,
  }) => _call('endSession', {'sessionId': sessionId});

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(functionName).call(data);
      final payload = result.data;
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (error) {
      final rawDetails = error.details;
      final details =
          rawDetails is Map
              ? Map<String, dynamic>.from(rawDetails)
              : const <String, dynamic>{};
      throw TutoringBackendException(
        error.code,
        error.message ?? 'Tutoring backend call failed.',
        errorCode:
            details['errorCode'] is String ? details['errorCode'] as String : null,
        details: details,
      );
    } catch (_) {
      throw const TutoringBackendException(
        'unknown',
        'Tutoring backend call failed.',
      );
    }
  }
}
