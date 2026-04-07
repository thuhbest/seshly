import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';
import 'paths.dart';

enum TeachMarkerType { check, warn, star }

enum ClassroomMemoryStrategy { cheapLive, expensiveWrap, manualRebuild }

class AiCaptureFrameRecord {
  const AiCaptureFrameRecord({
    required this.frameId,
    required this.frameType,
    required this.sourceCollection,
    required this.sourceId,
    required this.actorId,
    required this.studentId,
    required this.boardId,
    required this.taskId,
    required this.importance,
    required this.spotlightMode,
    required this.payload,
    required this.createdAt,
  });

  final String frameId;
  final String frameType;
  final String? sourceCollection;
  final String? sourceId;
  final String? actorId;
  final String? studentId;
  final String? boardId;
  final String? taskId;
  final String? importance;
  final String? spotlightMode;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  factory AiCaptureFrameRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AiCaptureFrameRecord(
      frameId: doc.id,
      frameType: _asString(data['frameType']) ?? 'unknown',
      sourceCollection: _asString(data['sourceCollection']),
      sourceId: _asString(data['sourceId']),
      actorId: _asString(data['actorId']),
      studentId: _asString(data['studentId']),
      boardId: _asString(data['boardId']),
      taskId: _asString(data['taskId']),
      importance: _asString(data['importance']),
      spotlightMode: _asString(data['spotlightMode']),
      payload: _asMap(data['payload']),
      createdAt: _asDateTime(data['createdAt']),
    );
  }
}

class ClassroomLessonSegment {
  const ClassroomLessonSegment({
    required this.label,
    required this.summary,
    required this.markerType,
    required this.startedAt,
    required this.endedAt,
  });

  final String label;
  final String summary;
  final String? markerType;
  final DateTime? startedAt;
  final DateTime? endedAt;

  factory ClassroomLessonSegment.fromMap(Map<String, dynamic> map) {
    return ClassroomLessonSegment(
      label: _asString(map['label']) ?? 'Lesson segment',
      summary: _asString(map['summary']) ?? '',
      markerType: _asString(map['markerType']),
      startedAt: _asDateTime(map['startedAt']),
      endedAt: _asDateTime(map['endedAt']),
    );
  }
}

class MisconceptionClusterRecord {
  const MisconceptionClusterRecord({
    required this.title,
    required this.misconception,
    required this.evidence,
    required this.reteachAction,
  });

  final String title;
  final String misconception;
  final List<String> evidence;
  final String reteachAction;

  factory MisconceptionClusterRecord.fromMap(Map<String, dynamic> map) {
    return MisconceptionClusterRecord(
      title: _asString(map['title']) ?? 'Misconception',
      misconception: _asString(map['misconception']) ?? '',
      evidence: _asStringList(map['evidence']),
      reteachAction: _asString(map['reteachAction']) ?? '',
    );
  }
}

class InterventionMomentRecord {
  const InterventionMomentRecord({
    required this.studentId,
    required this.title,
    required this.summary,
    required this.tutorAction,
    required this.followUp,
  });

  final String? studentId;
  final String title;
  final String summary;
  final String tutorAction;
  final String followUp;

  factory InterventionMomentRecord.fromMap(Map<String, dynamic> map) {
    return InterventionMomentRecord(
      studentId: _asString(map['studentId']),
      title: _asString(map['title']) ?? 'Intervention',
      summary: _asString(map['summary']) ?? '',
      tutorAction: _asString(map['tutorAction']) ?? '',
      followUp: _asString(map['followUp']) ?? '',
    );
  }
}

class ExemplarMomentRecord {
  const ExemplarMomentRecord({
    required this.studentId,
    required this.title,
    required this.whyItMatters,
    required this.boardId,
  });

  final String? studentId;
  final String title;
  final String whyItMatters;
  final String? boardId;

  factory ExemplarMomentRecord.fromMap(Map<String, dynamic> map) {
    return ExemplarMomentRecord(
      studentId: _asString(map['studentId']),
      title: _asString(map['title']) ?? 'Exemplar',
      whyItMatters: _asString(map['whyItMatters']) ?? '',
      boardId: _asString(map['boardId']),
    );
  }
}

class StudentLearningStateRecord {
  const StudentLearningStateRecord({
    required this.approach,
    required this.mistakes,
    required this.corrections,
    required this.stuckPoints,
    required this.nextFocusArea,
  });

  final List<String> approach;
  final List<String> mistakes;
  final List<String> corrections;
  final List<String> stuckPoints;
  final List<String> nextFocusArea;

  factory StudentLearningStateRecord.fromMap(Map<String, dynamic> map) {
    return StudentLearningStateRecord(
      approach: _asStringList(map['approach']),
      mistakes: _asStringList(map['mistakes']),
      corrections: _asStringList(map['corrections']),
      stuckPoints: _asStringList(map['stuckPoints']),
      nextFocusArea: _asStringList(map['nextFocusArea']),
    );
  }
}

class SessionContinuityNotesRecord {
  const SessionContinuityNotesRecord({
    required this.nextTutorShouldKnow,
    required this.reviseNextTime,
    required this.carryForwardTasks,
    required this.atRiskStudentIds,
  });

  final List<String> nextTutorShouldKnow;
  final List<String> reviseNextTime;
  final List<String> carryForwardTasks;
  final List<String> atRiskStudentIds;

  factory SessionContinuityNotesRecord.fromMap(Map<String, dynamic> map) {
    return SessionContinuityNotesRecord(
      nextTutorShouldKnow: _asStringList(map['nextTutorShouldKnow']),
      reviseNextTime: _asStringList(map['reviseNextTime']),
      carryForwardTasks: _asStringList(map['carryForwardTasks']),
      atRiskStudentIds: _asStringList(map['atRiskStudentIds']),
    );
  }

  static const empty = SessionContinuityNotesRecord(
    nextTutorShouldKnow: [],
    reviseNextTime: [],
    carryForwardTasks: [],
    atRiskStudentIds: [],
  );
}

class ClassroomMemorySnapshot {
  const ClassroomMemorySnapshot({
    required this.status,
    required this.strategy,
    required this.modelTier,
    required this.provider,
    required this.model,
    required this.cacheKey,
    required this.fallbackUsed,
    required this.sourceFrameCount,
    required this.groupLessonMemory,
    required this.lessonSegments,
    required this.misconceptionClusters,
    required this.interventionMoments,
    required this.exemplarMoments,
    required this.studentLearningStates,
    required this.sessionContinuityNotes,
    required this.updatedAt,
  });

  final String status;
  final String strategy;
  final String modelTier;
  final String provider;
  final String model;
  final String? cacheKey;
  final bool fallbackUsed;
  final int sourceFrameCount;
  final Map<String, List<String>> groupLessonMemory;
  final List<ClassroomLessonSegment> lessonSegments;
  final List<MisconceptionClusterRecord> misconceptionClusters;
  final List<InterventionMomentRecord> interventionMoments;
  final List<ExemplarMomentRecord> exemplarMoments;
  final Map<String, StudentLearningStateRecord> studentLearningStates;
  final SessionContinuityNotesRecord sessionContinuityNotes;
  final DateTime? updatedAt;

  factory ClassroomMemorySnapshot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final groupLessonMemory = _asMap(data['groupLessonMemory']);
    final studentLearningStatesMap = _asMap(data['studentLearningStates']);
    return ClassroomMemorySnapshot(
      status: _asString(data['status']) ?? 'processing',
      strategy: _asString(data['strategy']) ?? 'cheap_live',
      modelTier: _asString(data['modelTier']) ?? 'cheap',
      provider: _asString(data['provider']) ?? 'unknown',
      model: _asString(data['model']) ?? 'unknown',
      cacheKey: _asString(data['cacheKey']),
      fallbackUsed: data['fallbackUsed'] == true,
      sourceFrameCount: _asInt(data['sourceFrameCount']),
      groupLessonMemory: {
        'whatWasTaught': _asStringList(groupLessonMemory['whatWasTaught']),
        'keyMisconceptions': _asStringList(groupLessonMemory['keyMisconceptions']),
        'importantExamples': _asStringList(groupLessonMemory['importantExamples']),
        'reteachMoments': _asStringList(groupLessonMemory['reteachMoments']),
      },
      lessonSegments: _asListOfMaps(data['lessonSegments'])
          .map(ClassroomLessonSegment.fromMap)
          .toList(growable: false),
      misconceptionClusters: _asListOfMaps(data['misconceptionClusters'])
          .map(MisconceptionClusterRecord.fromMap)
          .toList(growable: false),
      interventionMoments: _asListOfMaps(data['interventionMoments'])
          .map(InterventionMomentRecord.fromMap)
          .toList(growable: false),
      exemplarMoments: _asListOfMaps(data['exemplarMoments'])
          .map(ExemplarMomentRecord.fromMap)
          .toList(growable: false),
      studentLearningStates: studentLearningStatesMap.map(
        (key, value) => MapEntry(key, StudentLearningStateRecord.fromMap(_asMap(value))),
      ),
      sessionContinuityNotes: SessionContinuityNotesRecord.fromMap(
        _asMap(data['sessionContinuityNotes']),
      ),
      updatedAt: _asDateTime(data['updatedAt']),
    );
  }

  static const empty = ClassroomMemorySnapshot(
    status: 'processing',
    strategy: 'cheap_live',
    modelTier: 'cheap',
    provider: 'unknown',
    model: 'unknown',
    cacheKey: null,
    fallbackUsed: false,
    sourceFrameCount: 0,
    groupLessonMemory: {
      'whatWasTaught': [],
      'keyMisconceptions': [],
      'importantExamples': [],
      'reteachMoments': [],
    },
    lessonSegments: [],
    misconceptionClusters: [],
    interventionMoments: [],
    exemplarMoments: [],
    studentLearningStates: {},
    sessionContinuityNotes: SessionContinuityNotesRecord.empty,
    updatedAt: null,
  );
}

class ClassroomMemoryService {
  ClassroomMemoryService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required String baseUrl,
  })  : _auth = auth,
        _firestore = firestore,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final String _baseUrl;

  Stream<ClassroomMemorySnapshot> watchSnapshot(String sessionId) {
    return _sessionRef(sessionId)
        .collection(Paths.aiMemory)
        .doc('current')
        .snapshots()
        .map(ClassroomMemorySnapshot.fromDoc);
  }

  Stream<List<AiCaptureFrameRecord>> watchFrames(String sessionId, {int limit = 40}) {
    return _sessionRef(sessionId)
        .collection(Paths.aiCaptureFrames)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(AiCaptureFrameRecord.fromDoc)
            .toList(growable: false));
  }

  Future<Map<String, dynamic>> addTeachMarker({
    required String sessionId,
    required SessionRole role,
    required TeachMarkerType markerType,
    String? label,
    String? note,
    String? boardId,
    String? taskId,
    String? studentId,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/memory/teachMarker', {
      'sessionId': sessionId,
      'markerType': _markerTypeToWire(markerType),
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (boardId != null && boardId.trim().isNotEmpty) 'boardId': boardId.trim(),
      if (taskId != null && taskId.trim().isNotEmpty) 'taskId': taskId.trim(),
      if (studentId != null && studentId.trim().isNotEmpty) 'studentId': studentId.trim(),
    });
  }

  Future<Map<String, dynamic>> addTutorAnnotation({
    required String sessionId,
    required SessionRole role,
    required String targetType,
    required String targetId,
    required String annotationText,
    String? boardId,
    String? taskId,
    String? studentId,
    List<String> tags = const [],
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/memory/annotate', {
      'sessionId': sessionId,
      'targetType': targetType.trim(),
      'targetId': targetId.trim(),
      'annotationText': annotationText.trim(),
      if (boardId != null && boardId.trim().isNotEmpty) 'boardId': boardId.trim(),
      if (taskId != null && taskId.trim().isNotEmpty) 'taskId': taskId.trim(),
      if (studentId != null && studentId.trim().isNotEmpty) 'studentId': studentId.trim(),
      if (tags.isNotEmpty)
        'tags': tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList(growable: false),
    });
  }

  Future<Map<String, dynamic>> addTranscriptPointer({
    required String sessionId,
    required SessionRole role,
    required String targetType,
    required String targetId,
    required int offsetMs,
    String? label,
    String? boardId,
    String? taskId,
    String? studentId,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/memory/transcriptPointer', {
      'sessionId': sessionId,
      'targetType': targetType.trim(),
      'targetId': targetId.trim(),
      'offsetMs': offsetMs,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (boardId != null && boardId.trim().isNotEmpty) 'boardId': boardId.trim(),
      if (taskId != null && taskId.trim().isNotEmpty) 'taskId': taskId.trim(),
      if (studentId != null && studentId.trim().isNotEmpty) 'studentId': studentId.trim(),
    });
  }

  Future<Map<String, dynamic>> requestRefresh({
    required String sessionId,
    required SessionRole role,
    ClassroomMemoryStrategy strategy = ClassroomMemoryStrategy.manualRebuild,
    String? reason,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/memory/refresh', {
      'sessionId': sessionId,
      'strategy': _strategyToWire(strategy),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  DocumentReference<Map<String, dynamic>> _sessionRef(String sessionId) {
    return _firestore.collection(Paths.sessions).doc(sessionId);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

String _markerTypeToWire(TeachMarkerType value) {
  switch (value) {
    case TeachMarkerType.check:
      return 'check';
    case TeachMarkerType.warn:
      return 'warn';
    case TeachMarkerType.star:
      return 'star';
  }
}

String _strategyToWire(ClassroomMemoryStrategy value) {
  switch (value) {
    case ClassroomMemoryStrategy.cheapLive:
      return 'cheap_live';
    case ClassroomMemoryStrategy.expensiveWrap:
      return 'expensive_wrap';
    case ClassroomMemoryStrategy.manualRebuild:
      return 'manual_rebuild';
  }
}

String? _asString(Object? value) => value is String ? value.trim() : null;

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asListOfMaps(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => _asMap(item)).toList(growable: false);
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList(growable: false);
}

DateTime? _asDateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
