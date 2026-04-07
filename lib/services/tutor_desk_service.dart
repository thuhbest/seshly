import 'package:cloud_firestore/cloud_firestore.dart';

import 'tutor_identity_service.dart';

class TutorDeskService {
  TutorDeskService({
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> updateAvailability({
    required String userId,
    required TutorAvailabilityState availability,
  }) {
    final Map<String, dynamic> payload;
    switch (availability) {
      case TutorAvailabilityState.accepting:
        payload = {
          'tutorRequestsEnabled': true,
          'tutorAvailability': 'accepting',
          'tutorActiveAt': FieldValue.serverTimestamp(),
        };
        break;
      case TutorAvailabilityState.afterCurrent:
        payload = {
          'tutorRequestsEnabled': false,
          'tutorAvailability': 'after_current',
          'tutorAfterCurrentAt': FieldValue.serverTimestamp(),
        };
        break;
      case TutorAvailabilityState.offline:
        payload = {
          'tutorRequestsEnabled': false,
          'tutorAvailability': 'offline',
          'tutorOfflineAt': FieldValue.serverTimestamp(),
        };
        break;
    }

    return _db.collection('users').doc(userId).set(
          payload,
          SetOptions(merge: true),
        );
  }
}
