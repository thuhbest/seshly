import 'package:cloud_firestore/cloud_firestore.dart';

import 'tutor_identity_service.dart';

class RankedTutorResult {
  const RankedTutorResult({
    required this.doc,
    required this.data,
    required this.tutor,
    required this.score,
  });

  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final TutorIdentity tutor;
  final double score;
}

class TutorRankingService {
  static List<RankedTutorResult> rankTutorDocs(
    List<QueryDocumentSnapshot> docs,
  ) {
    final ranked = docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final tutor = TutorIdentityService.fromUserData(data);
      return RankedTutorResult(
        doc: doc,
        data: data,
        tutor: tutor,
        score: _scoreTutor(tutor, isOnline: data['isOnline'] == true),
      );
    }).toList();

    ranked.sort((left, right) {
      final leftGold = left.tutor.goldTick.rankingBoostEnabled ? 1 : 0;
      final rightGold = right.tutor.goldTick.rankingBoostEnabled ? 1 : 0;
      if (leftGold != rightGold) return rightGold.compareTo(leftGold);

      final scoreComparison = right.score.compareTo(left.score);
      if (scoreComparison != 0) return scoreComparison;

      return left.tutor.pricing.totalRatePerMinute.compareTo(
        right.tutor.pricing.totalRatePerMinute,
      );
    });

    return ranked;
  }

  static double _scoreTutor(TutorIdentity tutor, {required bool isOnline}) {
    final ratingScore = tutor.performance.hasRating
        ? tutor.performance.ratingAverage * 12
        : 0;
    final qualitySessionScore =
        tutor.performance.qualifyingSessionCount.clamp(0, 120) * 2.8;
    final totalSessionScore =
        tutor.performance.sessionsCompleted.clamp(0, 250) * 0.8;
    final availabilityScore = tutor.canReceiveRequests ? 20 : 0;
    final onlineScore = isOnline ? 8 : 0;
    final goldBoost = tutor.goldTick.rankingBoostEnabled ? 250 : 0;

    return goldBoost +
        ratingScore +
        qualitySessionScore +
        totalSessionScore +
        availabilityScore +
        onlineScore;
  }
}
