import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/services/tutoring_backend_service.dart';

class TutorReviewException implements Exception {
  const TutorReviewException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'TutorReviewException($code): $message';
}

class PendingTutorReview {
  const PendingTutorReview({
    required this.paymentIntentId,
    required this.requestId,
    required this.studentId,
    required this.tutorId,
    required this.tutorName,
    required this.subject,
    required this.topic,
    required this.billableMinutes,
    required this.qualifiesForGoldTick,
    required this.settledAt,
  });

  final String paymentIntentId;
  final String requestId;
  final String studentId;
  final String tutorId;
  final String tutorName;
  final String subject;
  final String topic;
  final int billableMinutes;
  final bool qualifiesForGoldTick;
  final DateTime? settledAt;

  factory PendingTutorReview.fromIntent(
    String paymentIntentId,
    Map<String, dynamic> data,
  ) {
    return PendingTutorReview(
      paymentIntentId: paymentIntentId,
      requestId: (data['requestId'] ?? paymentIntentId).toString(),
      studentId: (data['studentId'] ?? '').toString(),
      tutorId: (data['tutorId'] ?? '').toString(),
      tutorName: (data['tutorName'] ?? 'Tutor').toString(),
      subject: (data['subject'] ?? 'Tutoring').toString(),
      topic: (data['topic'] ?? '').toString(),
      billableMinutes: (data['billableMinutes'] as num?)?.toInt() ?? 0,
      qualifiesForGoldTick: data['goldTickQualifiedSession'] == true,
      settledAt: (data['settledAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TutorReviewService {
  TutorReviewService({
    FirebaseFirestore? firestore,
    TutoringBackendService? backend,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _backend = backend ?? TutoringBackendService();

  final FirebaseFirestore _db;
  final TutoringBackendService _backend;

  Stream<List<PendingTutorReview>> pendingReviewsForStudent(String userId) {
    return _db
        .collection('session_payment_intents')
        .where('studentId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final pending =
              snapshot.docs
                  .where((doc) {
                    final data = doc.data();
                    final status = (data['reviewStatus'] ?? '').toString();
                    final settlement = (data['settlementStatus'] ?? '')
                        .toString();
                    return status == 'pending' &&
                        (settlement == 'completed' || settlement == 'partial');
                  })
                  .map(
                    (doc) => PendingTutorReview.fromIntent(doc.id, doc.data()),
                  )
                  .toList()
                ..sort((left, right) {
                  final leftDate = left.settledAt?.millisecondsSinceEpoch ?? 0;
                  final rightDate =
                      right.settledAt?.millisecondsSinceEpoch ?? 0;
                  return rightDate.compareTo(leftDate);
                });
          return pending;
        });
  }

  Future<void> submitReview({
    required User user,
    required PendingTutorReview pending,
    required double ratingOutOf10,
    String note = '',
  }) async {
    if (ratingOutOf10 < 1 || ratingOutOf10 > 10) {
      throw const TutorReviewException(
        'invalid_rating',
        'Choose a rating between 1 and 10.',
      );
    }
    final stars = (ratingOutOf10 / 2).round().clamp(1, 5);

    try {
      await _backend.submitTutoringRating(
        bookingId: pending.requestId,
        stars: stars,
        reviewText: note.trim(),
      );
    } on TutoringBackendException catch (error) {
      throw TutorReviewException(error.code, error.message);
    }
  }
}
