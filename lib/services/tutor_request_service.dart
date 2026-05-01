import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/services/billing_profile_service.dart';
import 'package:seshly/services/tutoring_backend_service.dart';
import 'package:seshly/services/tutor_organization_service.dart';
import 'package:seshly/services/tutor_session_service.dart';

class TutorRequestException implements Exception {
  const TutorRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'TutorRequestException($code): $message';
}

class TutorRequestAcceptanceResult {
  const TutorRequestAcceptanceResult({
    required this.startAt,
    required this.endAt,
    required this.bookingMode,
  });

  final DateTime startAt;
  final DateTime endAt;
  final TutorBookingMode bookingMode;
}

class TutorRequestService {
  TutorRequestService({TutoringBackendService? backend})
    : _backend = backend ?? TutoringBackendService();

  final TutoringBackendService _backend;

  Future<void> createRequest({
    required User user,
    required Map<String, dynamic> studentData,
    required Map<String, dynamic> tutorData,
    required String tutorId,
    required String subject,
    required String topic,
    required String questionText,
    required String? postId,
    required TutorBookingMode bookingMode,
    required TutorPricingBreakdown pricing,
    required String accessTier,
    required String accountType,
  }) async {
    if (subject.trim().isEmpty) {
      throw const TutorRequestException(
        'missing_subject',
        'Select a subject first.',
      );
    }

    final billingProfile = BillingProfileService.fromUserData(
      studentData,
      isAnonymousAuth: user.isAnonymous,
    );
    if (!billingProfile.canAuthorizeTutoring) {
      throw TutorRequestException(
        'missing_payment_method',
        billingProfile.isTemporary
            ? 'Link a temporary tutor-booking card before requesting a tutor.'
            : 'Set up your default card before requesting a tutor.',
      );
    }

    final studentName =
        (studentData['fullName'] ?? studentData['displayName'] ?? 'Student')
            .toString();
    final tutorName =
        (tutorData['fullName'] ?? tutorData['displayName'] ?? 'Tutor')
            .toString();
    final organization = TutorOrganizationService.membershipFromUserData(
      tutorData,
    );
    final requestedStart = TutorSessionService.computeRequestedStart(
      bookingMode: bookingMode,
    );
    try {
      final booking = await _backend.createTutoringBooking({
        'studentId': user.uid,
        'tutorId': tutorId,
        'requestType': _requestTypeForBookingMode(bookingMode),
        'bookingMode': bookingMode.value,
        'scheduledAt': requestedStart.toUtc().toIso8601String(),
        'tutorRatePerMinZar': pricing.tutorRatePerMinute,
        'idempotencyKey': [
          user.uid,
          tutorId,
          subject,
          topic,
          bookingMode.value,
          questionText.trim(),
          postId ?? '',
        ].join('|'),
        'subject': subject,
        'topic': topic,
        'questionText': questionText,
        'postId': postId,
        'prepMinutes': bookingMode.prepMinutes,
        'paymentProfileType': billingProfile.paymentProfileType,
        'paymentMethodSummary': billingProfile.summary,
        'studentAccessTier': accessTier,
        'studentAccountType': accountType,
        'organizationId': organization.organizationId,
        'organizationName': organization.organizationName,
        'organizationLogoUrl': organization.organizationLogoUrl,
        'organizationMemberTitle': organization.memberTitle,
        'organizationRole': organization.role.value,
        'organizationRatingAverage10': organization.organizationRatingAverage10,
        'studentName': studentName,
        'tutorName': tutorName,
      });
      final bookingId = (booking['bookingId'] ?? '').toString();
      if (bookingId.isEmpty) {
        throw const TutorRequestException(
          'booking_failed',
          'Could not create the tutoring booking.',
        );
      }
      await _backend.startTutoringPreauth(bookingId: bookingId);
    } on TutoringBackendException catch (error) {
      throw TutorRequestException(error.code, _mapBackendMessage(error));
    }
  }

  Future<TutorRequestAcceptanceResult> acceptRequest({
    required String requestId,
    required Map<String, dynamic> requestData,
    required DateTime startAt,
  }) async {
    final bookingMode = TutorBookingModeX.fromValue(
      requestData['bookingMode']?.toString(),
    );
    try {
      final response = await _backend.respondToTutoringBooking(
        bookingId: requestId,
        action: 'accept',
        scheduledAtIso: startAt.toUtc().toIso8601String(),
      );
      final scheduledAt =
          DateTime.tryParse((response['scheduledAt'] ?? '').toString()) ??
          startAt.toUtc();
      return TutorRequestAcceptanceResult(
        startAt: scheduledAt.toLocal(),
        endAt: scheduledAt.toLocal(),
        bookingMode: bookingMode,
      );
    } on TutoringBackendException catch (error) {
      throw TutorRequestException(error.code, _mapBackendMessage(error));
    }
  }

  Future<void> declineRequest(String requestId) async {
    try {
      await _backend.respondToTutoringBooking(
        bookingId: requestId,
        action: 'decline',
      );
    } on TutoringBackendException catch (error) {
      throw TutorRequestException(error.code, _mapBackendMessage(error));
    }
  }

  static String _requestTypeForBookingMode(TutorBookingMode bookingMode) {
    switch (bookingMode) {
      case TutorBookingMode.prep5:
        return 'IN_5';
      case TutorBookingMode.instant:
        return 'INSTANT';
    }
  }

  static String _mapBackendMessage(TutoringBackendException error) {
    switch (error.code) {
      case 'failed-precondition':
        return error.message;
      case 'invalid-argument':
        return error.message;
      case 'permission-denied':
        return error.message;
      default:
        return error.message.isEmpty
            ? 'Tutoring request could not be completed.'
            : error.message;
    }
  }
}
