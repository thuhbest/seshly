import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MentorMatch {
  final String mentorId;
  final Map<String, dynamic> profile;
  final int score;
  final List<String> reasons;

  MentorMatch({
    required this.mentorId,
    required this.profile,
    required this.score,
    required this.reasons,
  });
}

class MentorshipService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  MentorshipService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('mentorship_profiles');
  CollectionReference<Map<String, dynamic>> get _mentorships =>
      _db.collection('mentorships');

  Future<Map<String, dynamic>?> getProfile(String userId) async {
    final doc = await _profiles.doc(userId).get();
    return doc.data();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile(String userId) {
    return _profiles.doc(userId).snapshots();
  }

  Future<void> upsertProfile({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    await _profiles.doc(userId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMentorshipsForUser(String userId) {
    return _mentorships
        .where('participants', arrayContains: userId)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMentorshipsForMentor(String mentorId) {
    return _mentorships
        .where('mentorId', isEqualTo: mentorId)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingRequestsForMentee(String menteeId) {
    return _mentorships
        .where('menteeId', isEqualTo: menteeId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  String _normalize(String? value) {
    return (value ?? '').toLowerCase().trim();
  }

  List<String> _listFrom(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  int _yearToNumber(String? level) {
    final value = _normalize(level);
    if (value.contains('1st') || value.contains('first')) return 1;
    if (value.contains('2nd') || value.contains('second')) return 2;
    if (value.contains('3rd') || value.contains('third')) return 3;
    if (value.contains('4th') || value.contains('fourth')) return 4;
    if (value.contains('honours')) return 4;
    if (value.contains('masters')) return 5;
    if (value.contains('phd')) return 6;
    final match = RegExp(r'\\d+').firstMatch(value);
    if (match != null) return int.tryParse(match.group(0) ?? '') ?? 0;
    return 0;
  }

  String focusThemeForMonth(DateTime now) {
    switch (now.month) {
      case 1:
        return 'Goal setting and study routines';
      case 2:
        return 'Time management and consistency';
      case 3:
        return 'Mid-term preparation';
      case 4:
        return 'Wellbeing and balance';
      case 5:
        return 'Assessment recovery and feedback';
      case 6:
        return 'Exam readiness';
      case 7:
        return 'Reflection and resilience';
      case 8:
        return 'Second-semester reset';
      case 9:
        return 'Project planning';
      case 10:
        return 'Exam strategy';
      case 11:
        return 'Final push and wellbeing';
      case 12:
        return 'Planning ahead';
      default:
        return 'Focus and consistency';
    }
  }

  List<String> talkingPointsForTheme(String theme, List<String> riskFlags) {
    final points = <String>[];
    if (riskFlags.contains('mood_struggling')) {
      points.add('Check in on stress and ask what feels hardest this week.');
    }
    if (riskFlags.contains('no_mentor_contact')) {
      points.add('Schedule a short call and confirm a weekly check-in routine.');
    }
    if (riskFlags.contains('goal_stagnation')) {
      points.add('Break goals into a single next action for the next 48 hours.');
    }
    if (riskFlags.contains('missed_events')) {
      points.add('Review upcoming calendar deadlines together.');
    }
    points.add('Theme: $theme');
    return points;
  }

  String _weekKey(DateTime date) {
    final firstDay = DateTime(date.year, 1, 1);
    final daysOffset = date.difference(firstDay).inDays;
    final week = (daysOffset / 7).floor() + 1;
    return '${date.year}-W${week.toString().padLeft(2, '0')}';
  }

  List<String> _overlap(List<String> a, List<String> b) {
    final setB = b.map(_normalize).toSet();
    return a.map(_normalize).where(setB.contains).toSet().toList();
  }

  int _scoreMatch(
    Map<String, dynamic> mentee,
    Map<String, dynamic> mentor,
    List<String> reasons,
  ) {
    int score = 40;
    final menteeFaculty = _normalize(mentee['faculty']?.toString());
    final mentorFaculty = _normalize(mentor['faculty']?.toString());
    if (menteeFaculty.isNotEmpty && menteeFaculty == mentorFaculty) {
      score += 20;
      reasons.add('Same faculty');
    }

    final menteeMajor = _normalize(mentee['major']?.toString());
    final mentorMajor = _normalize(mentor['major']?.toString());
    if (menteeMajor.isNotEmpty && mentorMajor.isNotEmpty) {
      if (menteeMajor == mentorMajor) {
        score += 15;
        reasons.add('Same course');
      } else if (mentorMajor.contains(menteeMajor) || menteeMajor.contains(mentorMajor)) {
        score += 10;
        reasons.add('Related course');
      }
    }

    final menteeDegree = _normalize(mentee['degree']?.toString());
    final mentorDegree = _normalize(mentor['degree']?.toString());
    if (menteeDegree.isNotEmpty && menteeDegree == mentorDegree) {
      score += 12;
      reasons.add('Same degree');
    }

    final menteeYear = _yearToNumber(mentee['year']?.toString() ?? mentee['levelOfStudy']?.toString());
    final mentorYear = _yearToNumber(mentor['year']?.toString() ?? mentor['levelOfStudy']?.toString());
    final yearGap = mentorYear - menteeYear;
    if (yearGap >= 1 && yearGap <= 2) {
      score += 12;
      reasons.add('Ideal year gap');
    } else if (yearGap >= 3) {
      score += 8;
      reasons.add('Experienced mentor');
    } else if (yearGap <= 0 && menteeYear > 0 && mentorYear > 0) {
      score -= 8;
    }

    final menteeBackground = mentee['background'] as Map<String, dynamic>? ?? {};
    final mentorBackground = mentor['background'] as Map<String, dynamic>? ?? {};
    if (menteeBackground['firstGen'] == true && mentorBackground['firstGen'] == true) {
      score += 6;
      reasons.add('First-gen match');
    }
    if (menteeBackground['international'] == true && mentorBackground['international'] == true) {
      score += 6;
      reasons.add('International student match');
    }
    final menteeFunding = _normalize(menteeBackground['fundingStatus']?.toString());
    final mentorFunding = _normalize(mentorBackground['fundingStatus']?.toString());
    if (menteeFunding.isNotEmpty && menteeFunding == mentorFunding) {
      score += 4;
      reasons.add('Funding background match');
    }

    final menteeCareers = _listFrom(mentee['careerInterests']);
    final mentorCareers = _listFrom(mentor['careerInterests']);
    final careerOverlap = _overlap(menteeCareers, mentorCareers);
    if (careerOverlap.isNotEmpty) {
      score += (careerOverlap.length * 5).clamp(5, 15);
      reasons.add('Career interest overlap');
    }

    final menteePersonality = _listFrom(mentee['personalityTags']);
    final mentorPersonality = _listFrom(mentor['personalityTags']);
    final personalityOverlap = _overlap(menteePersonality, mentorPersonality);
    if (personalityOverlap.isNotEmpty) {
      score += (personalityOverlap.length * 4).clamp(4, 12);
      reasons.add('Personality fit');
    }

    final menteeRisk = _listFrom(mentee['riskSignals']).map(_normalize).toList();
    final mentorFocus = _listFrom(mentor['focusAreas']).map(_normalize).toList();
    if (menteeRisk.contains('stress') && mentorFocus.contains('wellbeing')) {
      score += 6;
      reasons.add('Wellbeing support');
    }
    if (menteeRisk.contains('academics') && mentorFocus.contains('academics')) {
      score += 6;
      reasons.add('Academic focus');
    }

    return score.clamp(0, 100);
  }

  Future<List<MentorMatch>> findMentorMatches({
    required Map<String, dynamic> menteeProfile,
    int limit = 6,
  }) async {
    final menteeId = menteeProfile['userId']?.toString() ?? currentUserId;
    Query<Map<String, dynamic>> query = _profiles
        .where('role', isEqualTo: 'mentor')
        .where('status', isEqualTo: 'active');
    final university = _normalize(menteeProfile['university']?.toString());
    if (university.isNotEmpty) {
      query = query.where('university', isEqualTo: menteeProfile['university']);
    }

    final snapshot = await query.limit(40).get();
    final matches = <MentorMatch>[];
    for (final doc in snapshot.docs) {
      if (menteeId != null && doc.id == menteeId) continue;
      final mentorProfile = doc.data();
      final reasons = <String>[];
      final score = _scoreMatch(menteeProfile, mentorProfile, reasons);
      matches.add(MentorMatch(
        mentorId: doc.id,
        profile: mentorProfile,
        score: score,
        reasons: reasons,
      ));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(limit).toList();
  }

  Future<List<MentorMatch>> findMenteeMatches({
    required Map<String, dynamic> mentorProfile,
    int limit = 6,
  }) async {
    Query<Map<String, dynamic>> query = _profiles
        .where('role', isEqualTo: 'mentee')
        .where('status', isEqualTo: 'active');
    final university = _normalize(mentorProfile['university']?.toString());
    if (university.isNotEmpty) {
      query = query.where('university', isEqualTo: mentorProfile['university']);
    }

    final snapshot = await query.limit(40).get();
    final matches = <MentorMatch>[];
    for (final doc in snapshot.docs) {
      final menteeProfile = doc.data();
      final menteeId = doc.id;
      if (menteeId == currentUserId) continue;
      final reasons = <String>[];
      final score = _scoreMatch(menteeProfile, mentorProfile, reasons);
      matches.add(MentorMatch(
        mentorId: menteeId,
        profile: menteeProfile,
        score: score,
        reasons: reasons,
      ));
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(limit).toList();
  }

  Future<bool> _hasActiveMentorship(String menteeId) async {
    final existing = await _mentorships
        .where('menteeId', isEqualTo: menteeId)
        .where('status', whereIn: ['active', 'pending'])
        .limit(1)
        .get();
    return existing.docs.isNotEmpty;
  }

  Future<String?> createMentorship({
    required String mentorId,
    required String menteeId,
    int matchScore = 0,
    List<String> matchReasons = const [],
  }) async {
    final existing = await _mentorships
        .where('menteeId', isEqualTo: menteeId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final mentorProfile = await getProfile(mentorId) ?? {};
    final menteeProfile = await getProfile(menteeId) ?? {};
    final menteeYear = menteeProfile['year'] ?? menteeProfile['levelOfStudy'];
    final mentorYear = mentorProfile['year'] ?? mentorProfile['levelOfStudy'];

    final mentorUser = await _db.collection('users').doc(mentorId).get();
    final menteeUser = await _db.collection('users').doc(menteeId).get();
    final mentorName = (mentorUser.data()?['fullName'] ?? 'Mentor').toString();
    final menteeName = (menteeUser.data()?['fullName'] ?? 'Student').toString();

    final focusTheme = focusThemeForMonth(DateTime.now());
    final docRef = await _mentorships.add({
      'mentorId': mentorId,
      'menteeId': menteeId,
      'mentorName': mentorName,
      'menteeName': menteeName,
      'menteeYear': menteeYear,
      'mentorYear': mentorYear,
      'menteeYearNumber': _yearToNumber(menteeYear?.toString()),
      'mentorYearNumber': _yearToNumber(mentorYear?.toString()),
      'participants': [mentorId, menteeId],
      'status': 'active',
      'matchScore': matchScore,
      'matchReasons': matchReasons,
      'focusTheme': focusTheme,
      'riskScore': 0,
      'riskFlags': [],
      'checkInStreak': 0,
      'lastCheckInAt': null,
      'lastInteractionAt': null,
      'nextCheckInDueAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'university': menteeProfile['university'] ?? mentorProfile['university'],
      'faculty': menteeProfile['faculty'] ?? mentorProfile['faculty'],
      'degree': menteeProfile['degree'] ?? mentorProfile['degree'],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'privacy': {
        'optIn': menteeProfile['optIn'] == true,
        'anonymized': true,
      },
    });

    await _profiles.doc(mentorId).set({
      'activeMentorshipId': docRef.id,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _profiles.doc(menteeId).set({
      'activeMentorshipId': docRef.id,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return docRef.id;
  }

  Future<String?> createMentorshipRequest({
    required String mentorId,
    required String menteeId,
    int matchScore = 0,
    List<String> matchReasons = const [],
    String requestSource = 'university',
  }) async {
    if (await _hasActiveMentorship(menteeId)) {
      return null;
    }

    final mentorProfile = await getProfile(mentorId) ?? {};
    final menteeProfile = await getProfile(menteeId) ?? {};
    final menteeYear = menteeProfile['year'] ?? menteeProfile['levelOfStudy'];
    final mentorYear = mentorProfile['year'] ?? mentorProfile['levelOfStudy'];

    final mentorUser = await _db.collection('users').doc(mentorId).get();
    final menteeUser = await _db.collection('users').doc(menteeId).get();
    final mentorName = (mentorUser.data()?['fullName'] ?? 'Mentor').toString();
    final menteeName = (menteeUser.data()?['fullName'] ?? 'Student').toString();

    final focusTheme = focusThemeForMonth(DateTime.now());
    final docRef = await _mentorships.add({
      'mentorId': mentorId,
      'menteeId': menteeId,
      'mentorName': mentorName,
      'menteeName': menteeName,
      'menteeYear': menteeYear,
      'mentorYear': mentorYear,
      'menteeYearNumber': _yearToNumber(menteeYear?.toString()),
      'mentorYearNumber': _yearToNumber(mentorYear?.toString()),
      'participants': [mentorId, menteeId],
      'status': 'pending',
      'matchScore': matchScore,
      'matchReasons': matchReasons,
      'focusTheme': focusTheme,
      'riskScore': 0,
      'riskFlags': [],
      'checkInStreak': 0,
      'lastCheckInAt': null,
      'lastInteractionAt': null,
      'nextCheckInDueAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      'university': menteeProfile['university'] ?? mentorProfile['university'],
      'faculty': menteeProfile['faculty'] ?? mentorProfile['faculty'],
      'degree': menteeProfile['degree'] ?? mentorProfile['degree'],
      'requestSource': requestSource,
      'requestedBy': mentorId,
      'requestedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'privacy': {
        'optIn': menteeProfile['optIn'] == true,
        'anonymized': true,
      },
    });

    return docRef.id;
  }

  Future<String?> autoAssignMentee({required String mentorId}) async {
    final mentorProfile = await getProfile(mentorId) ?? {};
    if (mentorProfile.isEmpty) {
      return null;
    }
    final matches = await findMenteeMatches(mentorProfile: mentorProfile, limit: 12);
    for (final match in matches) {
      final menteeId = match.mentorId;
      if (await _hasActiveMentorship(menteeId)) {
        continue;
      }
      return createMentorshipRequest(
        mentorId: mentorId,
        menteeId: menteeId,
        matchScore: match.score,
        matchReasons: match.reasons,
        requestSource: 'university',
      );
    }
    return null;
  }

  Future<void> acceptMentorshipRequest({required String mentorshipId}) async {
    final doc = await _mentorships.doc(mentorshipId).get();
    final data = doc.data() ?? {};
    final mentorId = (data['mentorId'] ?? '').toString();
    final menteeId = (data['menteeId'] ?? '').toString();
    if (mentorId.isEmpty || menteeId.isEmpty) return;

    await _mentorships.doc(mentorshipId).update({
      'status': 'active',
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _profiles.doc(mentorId).set({
      'activeMentorshipId': mentorshipId,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _profiles.doc(menteeId).set({
      'activeMentorshipId': mentorshipId,
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> declineMentorshipRequest({required String mentorshipId}) async {
    await _mentorships.doc(mentorshipId).update({
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitCheckIn({
    required String mentorshipId,
    required String userId,
    required String mood,
    String? note,
  }) async {
    final now = DateTime.now();
    final checkinsRef = _mentorships.doc(mentorshipId).collection('checkins');
    final userDoc = await _db.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? {};

    await checkinsRef.add({
      'userId': userId,
      'mood': mood,
      'note': note ?? '',
      'weekKey': _weekKey(now),
      'faculty': userData['faculty'],
      'degree': userData['degree'],
      'university': userData['university'],
      'createdAt': FieldValue.serverTimestamp(),
    });

    final recent = await checkinsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(3)
        .get();

    final moods = recent.docs.map((doc) => (doc.data()['mood'] ?? '').toString()).toList();
    final strugglingCount = moods.where((m) => m == 'struggling').length;

    final mentorshipDoc = await _mentorships.doc(mentorshipId).get();
    final mentorshipData = mentorshipDoc.data() ?? {};
    final riskFlags = List<String>.from(mentorshipData['riskFlags'] ?? []);

    if (strugglingCount >= 2 && !riskFlags.contains('mood_struggling')) {
      riskFlags.add('mood_struggling');
    }

    final lastInteractionAt = mentorshipData['lastInteractionAt'] as Timestamp?;
    if (lastInteractionAt != null) {
      final diff = now.difference(lastInteractionAt.toDate()).inDays;
      if (diff >= 10 && !riskFlags.contains('no_mentor_contact')) {
        riskFlags.add('no_mentor_contact');
      }
    }

    final goalsSnap = await _mentorships
        .doc(mentorshipId)
        .collection('goals')
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .get();
    if (goalsSnap.docs.isNotEmpty) {
      final lastGoalUpdate = goalsSnap.docs.first.data()['updatedAt'] as Timestamp?;
      if (lastGoalUpdate != null) {
        final diff = now.difference(lastGoalUpdate.toDate()).inDays;
        if (diff >= 21 && !riskFlags.contains('goal_stagnation')) {
          riskFlags.add('goal_stagnation');
        }
      }
    }

    final missedEvents = (userData['missedEventsCount'] as num?)?.toInt() ?? 0;
    if (missedEvents >= 2 && !riskFlags.contains('missed_events')) {
      riskFlags.add('missed_events');
    }

    final riskScore =
        (strugglingCount * 20) + (riskFlags.contains('no_mentor_contact') ? 15 : 0) + (riskFlags.contains('goal_stagnation') ? 10 : 0);

    final lastCheckInAt = mentorshipData['lastCheckInAt'] as Timestamp?;
    int checkInStreak = (mentorshipData['checkInStreak'] as num?)?.toInt() ?? 0;
    if (lastCheckInAt != null) {
      final diffDays = now.difference(lastCheckInAt.toDate()).inDays;
      if (diffDays <= 7) {
        checkInStreak += 1;
      } else {
        checkInStreak = 1;
      }
    } else {
      checkInStreak = 1;
    }

    await _mentorships.doc(mentorshipId).update({
      'lastCheckInAt': FieldValue.serverTimestamp(),
      'lastMood': mood,
      'riskScore': riskScore.clamp(0, 100),
      'riskFlags': riskFlags,
      'checkInStreak': checkInStreak,
      'nextCheckInDueAt': Timestamp.fromDate(now.add(const Duration(days: 7))),
      'focusTheme': focusThemeForMonth(now),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> logMentorInteraction(String mentorshipId) async {
    await _mentorships.doc(mentorshipId).update({
      'lastInteractionAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordIntervention({
    required String mentorshipId,
    required String action,
    String note = '',
  }) async {
    final actorId = currentUserId;
    await _mentorships.doc(mentorshipId).collection('interventions').add({
      'action': action,
      'note': note,
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _mentorships.doc(mentorshipId).update({
      'lastInterventionAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addGoal({
    required String mentorshipId,
    required String title,
    required String type,
    required String dueLabel,
    int target = 100,
  }) async {
    await _mentorships.doc(mentorshipId).collection('goals').add({
      'title': title,
      'type': type,
      'dueLabel': dueLabel,
      'progress': 0,
      'target': target,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGoalProgress({
    required String mentorshipId,
    required String goalId,
    required int progress,
  }) async {
    await _mentorships.doc(mentorshipId).collection('goals').doc(goalId).update({
      'progress': progress,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
