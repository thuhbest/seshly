import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';
import 'paths.dart';

enum ClassroomRoomMode { teach, practice, review }

enum ClassroomFocusMode { wholeClass, spotlightStudent, tutorPrivateReview }

enum ClassroomSpotlightMode { none, soft, hard }

enum ClassroomBoardMode { sharedBoard, studentPrivateBoards, reviewBoard }

enum InterventionState {
  none,
  nudged,
  tutorObserving,
  tutorIntervening,
  correctionSent,
}

enum ParticipantVisibilityState {
  classVisible,
  privateBoardOnly,
  spotlighted,
  reviewVisible,
}

enum ClassroomParticipantFocusState {
  inClass,
  privateWork,
  underIntervention,
  presentingToClass,
  inReview,
  monitoringGrid,
  inIntervention,
  presentingReview,
}

enum ClassroomEventType {
  modeChanged,
  focusChanged,
  taskStarted,
  taskCollected,
  spotlightStarted,
  spotlightEnded,
  studentBoardBroadcast,
  returnToClass,
  sessionEnded,
  unknown,
}

class ClassroomSubmissionSummary {
  const ClassroomSubmissionSummary({
    required this.expectedStudentCount,
    required this.submittedStudentCount,
    required this.collected,
    this.collectedAt,
    required this.collectedSnapshotCount,
  });

  final int expectedStudentCount;
  final int submittedStudentCount;
  final bool collected;
  final DateTime? collectedAt;
  final int collectedSnapshotCount;

  factory ClassroomSubmissionSummary.fromMap(Map<String, dynamic> map) {
    return ClassroomSubmissionSummary(
      expectedStudentCount: _asInt(map['expectedStudentCount']),
      submittedStudentCount: _asInt(map['submittedStudentCount']),
      collected: map['collected'] == true,
      collectedAt: _asDateTime(map['collectedAt']),
      collectedSnapshotCount: _asInt(map['collectedSnapshotCount']),
    );
  }

  static const empty = ClassroomSubmissionSummary(
    expectedStudentCount: 0,
    submittedStudentCount: 0,
    collected: false,
    collectedAt: null,
    collectedSnapshotCount: 0,
  );
}

class ClassroomSpotlightState {
  const ClassroomSpotlightState({
    required this.active,
    required this.mode,
    required this.pauseOthers,
    required this.deEmphasizeOthers,
    required this.studentId,
    required this.observeOnly,
    required this.reason,
    required this.boardId,
    required this.startedAt,
    required this.startedBy,
    required this.momentId,
    required this.auditId,
  });

  final bool active;
  final ClassroomSpotlightMode mode;
  final bool pauseOthers;
  final bool deEmphasizeOthers;
  final String? studentId;
  final bool observeOnly;
  final String? reason;
  final String? boardId;
  final DateTime? startedAt;
  final String? startedBy;
  final String? momentId;
  final String? auditId;

  factory ClassroomSpotlightState.fromMap(Map<String, dynamic> map) {
    return ClassroomSpotlightState(
      active: map['active'] == true,
      mode: _spotlightModeFromString(_asString(map['mode'])),
      pauseOthers: map['pauseOthers'] == true,
      deEmphasizeOthers: map['deEmphasizeOthers'] == true,
      studentId: _asString(map['studentId']),
      observeOnly: map['observeOnly'] == true,
      reason: _asString(map['reason']),
      boardId: _asString(map['boardId']),
      startedAt: _asDateTime(map['startedAt']),
      startedBy: _asString(map['startedBy']),
      momentId: _asString(map['momentId']),
      auditId: _asString(map['auditId']),
    );
  }

  static const inactive = ClassroomSpotlightState(
    active: false,
    mode: ClassroomSpotlightMode.none,
    pauseOthers: false,
    deEmphasizeOthers: false,
    studentId: null,
    observeOnly: false,
    reason: null,
    boardId: null,
    startedAt: null,
    startedBy: null,
    momentId: null,
    auditId: null,
  );
}

class ClassroomState {
  const ClassroomState({
    required this.roomMode,
    required this.focusMode,
    required this.boardMode,
    required this.callMode,
    required this.attentionTarget,
    required this.classLock,
    required this.activeTaskId,
    required this.activeBoardRef,
    required this.activeInterventionId,
    required this.timerEndAt,
    required this.orchestratorVersion,
    required this.callModeVersion,
    required this.studentAnnotateEnabled,
    required this.submissionSummary,
    required this.spotlight,
    required this.updatedAt,
  });

  final ClassroomRoomMode roomMode;
  final ClassroomFocusMode focusMode;
  final ClassroomBoardMode boardMode;
  final String callMode;
  final String? attentionTarget;
  final bool classLock;
  final String? activeTaskId;
  final String? activeBoardRef;
  final String? activeInterventionId;
  final DateTime? timerEndAt;
  final int orchestratorVersion;
  final int callModeVersion;
  final bool studentAnnotateEnabled;
  final ClassroomSubmissionSummary submissionSummary;
  final ClassroomSpotlightState spotlight;
  final DateTime? updatedAt;

  factory ClassroomState.fromMap(Map<String, dynamic> map) {
    final settings = _asMap(map['settings']);
    final submissionSummary = _asMap(map['submissionSummary']);
    final spotlight = _asMap(map['spotlight']);
    return ClassroomState(
      roomMode: _roomModeFromString(_asString(map['roomMode']) ?? _asString(map['mode'])),
      focusMode: _focusModeFromString(_asString(map['focusMode'])),
      boardMode: _boardModeFromString(_asString(map['boardMode'])),
      callMode: _asString(map['callMode']) ?? 'p2p',
      attentionTarget: _asString(map['attentionTarget']),
      classLock: map['classLock'] != false,
      activeTaskId: _asString(map['activeTaskId']),
      activeBoardRef: _asString(map['activeBoardRef']),
      activeInterventionId: _asString(map['activeInterventionId']),
      timerEndAt: _asDateTime(map['timerEndAt']),
      orchestratorVersion: _asInt(map['orchestratorVersion'], fallback: 1),
      callModeVersion: _asInt(map['callModeVersion'], fallback: 1),
      studentAnnotateEnabled: settings['studentAnnotateEnabled'] == true,
      submissionSummary: ClassroomSubmissionSummary.fromMap(submissionSummary),
      spotlight: ClassroomSpotlightState.fromMap(spotlight),
      updatedAt: _asDateTime(map['updatedAt']),
    );
  }

  static const empty = ClassroomState(
    roomMode: ClassroomRoomMode.teach,
    focusMode: ClassroomFocusMode.wholeClass,
    boardMode: ClassroomBoardMode.sharedBoard,
    callMode: 'p2p',
    attentionTarget: null,
    classLock: true,
    activeTaskId: null,
    activeBoardRef: null,
    activeInterventionId: null,
    timerEndAt: null,
    orchestratorVersion: 1,
    callModeVersion: 1,
    studentAnnotateEnabled: false,
    submissionSummary: ClassroomSubmissionSummary.empty,
    spotlight: ClassroomSpotlightState.inactive,
    updatedAt: null,
  );
}

class ClassroomParticipantState {
  const ClassroomParticipantState({
    required this.participantId,
    required this.role,
    required this.joinState,
    required this.focusState,
    required this.visibilityState,
    required this.interventionState,
    required this.currentTaskId,
    required this.pinned,
    required this.lastOrchestratedAt,
    required this.data,
  });

  final String participantId;
  final String role;
  final String joinState;
  final ClassroomParticipantFocusState focusState;
  final ParticipantVisibilityState visibilityState;
  final InterventionState interventionState;
  final String? currentTaskId;
  final bool pinned;
  final DateTime? lastOrchestratedAt;
  final Map<String, dynamic> data;

  factory ClassroomParticipantState.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ClassroomParticipantState(
      participantId: doc.id,
      role: _asString(data['role']) ?? 'student',
      joinState: _asString(data['joinState']) ?? 'joined',
      focusState: _participantFocusFromString(_asString(data['classroomFocusState'])),
      visibilityState: _visibilityFromString(_asString(data['visibilityState'])),
      interventionState: _interventionFromString(_asString(data['interventionState'])),
      currentTaskId: _asString(data['currentTaskId']),
      pinned: data['pinned'] == true,
      lastOrchestratedAt: _asDateTime(data['lastOrchestratedAt']),
      data: data,
    );
  }
}

class ClassroomEvent {
  const ClassroomEvent({
    required this.eventId,
    required this.type,
    required this.actionId,
    required this.createdBy,
    required this.roomMode,
    required this.focusMode,
    required this.boardMode,
    required this.attentionTarget,
    required this.payload,
    required this.createdAt,
  });

  final String eventId;
  final ClassroomEventType type;
  final String? actionId;
  final String? createdBy;
  final ClassroomRoomMode roomMode;
  final ClassroomFocusMode focusMode;
  final ClassroomBoardMode boardMode;
  final String? attentionTarget;
  final Map<String, dynamic> payload;
  final DateTime? createdAt;

  factory ClassroomEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ClassroomEvent(
      eventId: doc.id,
      type: _eventTypeFromString(_asString(data['type'])),
      actionId: _asString(data['actionId']),
      createdBy: _asString(data['createdBy']),
      roomMode: _roomModeFromString(_asString(data['roomMode'])),
      focusMode: _focusModeFromString(_asString(data['focusMode'])),
      boardMode: _boardModeFromString(_asString(data['boardMode'])),
      attentionTarget: _asString(data['attentionTarget']),
      payload: _asMap(data['payload']),
      createdAt: _asDateTime(data['createdAt']),
    );
  }
}

class ClassroomAiMoment {
  const ClassroomAiMoment({
    required this.momentId,
    required this.type,
    required this.importance,
    required this.studentId,
    required this.boardId,
    required this.startedBy,
    required this.createdAt,
    required this.payload,
  });

  final String momentId;
  final String? type;
  final String? importance;
  final String? studentId;
  final String? boardId;
  final String? startedBy;
  final DateTime? createdAt;
  final Map<String, dynamic> payload;

  factory ClassroomAiMoment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return ClassroomAiMoment(
      momentId: doc.id,
      type: _asString(data['type']),
      importance: _asString(data['importance']),
      studentId: _asString(data['studentId']),
      boardId: _asString(data['boardId']),
      startedBy: _asString(data['startedBy']),
      createdAt: _asDateTime(data['createdAt']),
      payload: _asMap(data['payload']),
    );
  }
}

class SpotlightAuditEntry {
  const SpotlightAuditEntry({
    required this.auditId,
    required this.actionType,
    required this.studentId,
    required this.startedBy,
    required this.spotlightMode,
    required this.pauseOthers,
    required this.deEmphasizeOthers,
    required this.reason,
    required this.createdAt,
  });

  final String auditId;
  final String? actionType;
  final String? studentId;
  final String? startedBy;
  final ClassroomSpotlightMode spotlightMode;
  final bool pauseOthers;
  final bool deEmphasizeOthers;
  final String? reason;
  final DateTime? createdAt;

  factory SpotlightAuditEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return SpotlightAuditEntry(
      auditId: doc.id,
      actionType: _asString(data['actionType']),
      studentId: _asString(data['studentId']),
      startedBy: _asString(data['startedBy']),
      spotlightMode: _spotlightModeFromString(_asString(data['spotlightMode'])),
      pauseOthers: data['pauseOthers'] == true,
      deEmphasizeOthers: data['deEmphasizeOthers'] == true,
      reason: _asString(data['reason']),
      createdAt: _asDateTime(data['createdAt']),
    );
  }
}

class ClassroomActionAck {
  const ClassroomActionAck({
    required this.ok,
    required this.actionId,
    required this.payload,
  });

  final bool ok;
  final String actionId;
  final Map<String, dynamic> payload;

  factory ClassroomActionAck.fromPayload(
    Map<String, dynamic> payload, {
    required String actionId,
  }) {
    return ClassroomActionAck(
      ok: payload['ok'] != false,
      actionId: actionId,
      payload: payload,
    );
  }
}

class ClassroomOrchestratorService {
  ClassroomOrchestratorService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required String baseUrl,
  })  : _auth = auth,
        _firestore = firestore,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final String _baseUrl;

  Stream<ClassroomState> watchState(String sessionId) {
    return _sessionRef(sessionId)
        .collection(Paths.sessionState)
        .doc('sessionState')
        .snapshots()
        .map((doc) => ClassroomState.fromMap(doc.data() ?? <String, dynamic>{}));
  }

  Future<ClassroomState> getState(String sessionId) async {
    final doc = await _sessionRef(sessionId)
        .collection(Paths.sessionState)
        .doc('sessionState')
        .get();
    return ClassroomState.fromMap(doc.data() ?? <String, dynamic>{});
  }

  Stream<List<ClassroomParticipantState>> watchParticipants(String sessionId) {
    return _sessionRef(sessionId)
        .collection(Paths.participants)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(ClassroomParticipantState.fromDoc)
            .toList(growable: false));
  }

  Stream<List<ClassroomEvent>> watchEvents(
    String sessionId, {
    int limit = 40,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.sessionEvents)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(ClassroomEvent.fromDoc)
            .toList(growable: false));
  }

  Stream<List<ClassroomAiMoment>> watchAiMoments(
    String sessionId, {
    int limit = 20,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.aiMoments)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(ClassroomAiMoment.fromDoc)
            .toList(growable: false));
  }

  Stream<List<SpotlightAuditEntry>> watchSpotlightHistory(
    String sessionId, {
    int limit = 20,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.spotlightHistory)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(SpotlightAuditEntry.fromDoc)
            .toList(growable: false));
  }

  Future<ClassroomActionAck> teachAll({
    required String sessionId,
    required SessionRole role,
    bool classLock = true,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/teachAll', {
      'sessionId': sessionId,
      'classLock': classLock,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> sendClasswork({
    required String sessionId,
    required Map<String, dynamic> taskPayload,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/sendClasswork', {
      'sessionId': sessionId,
      'taskPayload': taskPayload,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> monitorEveryoneQuietly({
    required String sessionId,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/monitor', {
      'sessionId': sessionId,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> focusStudent({
    required String sessionId,
    required String studentId,
    required SessionRole role,
    bool observeOnly = false,
    ClassroomSpotlightMode spotlightMode = ClassroomSpotlightMode.hard,
    bool pauseOthers = false,
    bool deEmphasizeOthers = true,
    String? reason,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/focusStudent', {
      'sessionId': sessionId,
      'studentId': studentId,
      'observeOnly': observeOnly,
      'spotlightMode': _spotlightModeToWire(spotlightMode),
      'pauseOthers': pauseOthers,
      'deEmphasizeOthers': deEmphasizeOthers,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> softSpotlightStudent({
    required String sessionId,
    required String studentId,
    required SessionRole role,
    bool observeOnly = false,
    bool deEmphasizeOthers = true,
    String? reason,
    String? actionId,
  }) {
    return focusStudent(
      sessionId: sessionId,
      studentId: studentId,
      role: role,
      observeOnly: observeOnly,
      spotlightMode: ClassroomSpotlightMode.soft,
      pauseOthers: false,
      deEmphasizeOthers: deEmphasizeOthers,
      reason: reason,
      actionId: actionId,
    );
  }

  Future<ClassroomActionAck> hardSpotlightStudent({
    required String sessionId,
    required String studentId,
    required SessionRole role,
    bool observeOnly = false,
    bool pauseOthers = false,
    bool deEmphasizeOthers = true,
    String? reason,
    String? actionId,
  }) {
    return focusStudent(
      sessionId: sessionId,
      studentId: studentId,
      role: role,
      observeOnly: observeOnly,
      spotlightMode: ClassroomSpotlightMode.hard,
      pauseOthers: pauseOthers,
      deEmphasizeOthers: deEmphasizeOthers,
      reason: reason,
      actionId: actionId,
    );
  }

  Future<ClassroomActionAck> returnToClass({
    required String sessionId,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/returnToClass', {
      'sessionId': sessionId,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> collectTaskWork({
    required String sessionId,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/session/collectNow', {
      'sessionId': sessionId,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> showStudentBoardToGroup({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/showToGroup', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> sendCorrection({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    required String annotationsRef,
    required SessionRole role,
    String? voiceNoteRef,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/sendCorrection', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
      'annotationsRef': annotationsRef,
      if (voiceNoteRef != null && voiceNoteRef.trim().isNotEmpty)
        'voiceNoteRef': voiceNoteRef.trim(),
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  Future<ClassroomActionAck> endSessionWithStructuredOutputs({
    required String sessionId,
    required SessionRole role,
    Map<String, dynamic>? wrapOptions,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final resolvedActionId = actionId ?? nextActionId();
    final payload = await _post('/classroom/endSession', {
      'sessionId': sessionId,
      if (wrapOptions != null) 'wrapOptions': wrapOptions,
      'actionId': resolvedActionId,
    });
    return ClassroomActionAck.fromPayload(payload, actionId: resolvedActionId);
  }

  String nextActionId() => _sessionRef('_').collection(Paths.orchestratorActions).doc().id;

  DocumentReference<Map<String, dynamic>> _sessionRef(String sessionId) {
    return _firestore.collection(Paths.sessions).doc(sessionId);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, dynamic item) => MapEntry('$key', item));
  return <String, dynamic>{};
}

String? _asString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _asDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

ClassroomRoomMode _roomModeFromString(String? value) {
  switch (value) {
    case 'practice':
      return ClassroomRoomMode.practice;
    case 'review':
      return ClassroomRoomMode.review;
    case 'teach':
    default:
      return ClassroomRoomMode.teach;
  }
}

ClassroomFocusMode _focusModeFromString(String? value) {
  switch (value) {
    case 'spotlightStudent':
      return ClassroomFocusMode.spotlightStudent;
    case 'tutorPrivateReview':
      return ClassroomFocusMode.tutorPrivateReview;
    case 'wholeClass':
    default:
      return ClassroomFocusMode.wholeClass;
  }
}

ClassroomSpotlightMode _spotlightModeFromString(String? value) {
  switch (value) {
    case 'soft':
      return ClassroomSpotlightMode.soft;
    case 'hard':
      return ClassroomSpotlightMode.hard;
    case 'none':
    default:
      return ClassroomSpotlightMode.none;
  }
}

String _spotlightModeToWire(ClassroomSpotlightMode value) {
  switch (value) {
    case ClassroomSpotlightMode.soft:
      return 'soft';
    case ClassroomSpotlightMode.hard:
      return 'hard';
    case ClassroomSpotlightMode.none:
      return 'none';
  }
}

ClassroomBoardMode _boardModeFromString(String? value) {
  switch (value) {
    case 'studentPrivateBoards':
      return ClassroomBoardMode.studentPrivateBoards;
    case 'reviewBoard':
      return ClassroomBoardMode.reviewBoard;
    case 'sharedBoard':
    default:
      return ClassroomBoardMode.sharedBoard;
  }
}

ClassroomParticipantFocusState _participantFocusFromString(String? value) {
  switch (value) {
    case 'privateWork':
      return ClassroomParticipantFocusState.privateWork;
    case 'underIntervention':
      return ClassroomParticipantFocusState.underIntervention;
    case 'presentingToClass':
      return ClassroomParticipantFocusState.presentingToClass;
    case 'inReview':
      return ClassroomParticipantFocusState.inReview;
    case 'monitoringGrid':
      return ClassroomParticipantFocusState.monitoringGrid;
    case 'inIntervention':
      return ClassroomParticipantFocusState.inIntervention;
    case 'presentingReview':
      return ClassroomParticipantFocusState.presentingReview;
    case 'inClass':
    default:
      return ClassroomParticipantFocusState.inClass;
  }
}

ParticipantVisibilityState _visibilityFromString(String? value) {
  switch (value) {
    case 'privateBoardOnly':
      return ParticipantVisibilityState.privateBoardOnly;
    case 'spotlighted':
      return ParticipantVisibilityState.spotlighted;
    case 'reviewVisible':
      return ParticipantVisibilityState.reviewVisible;
    case 'classVisible':
    default:
      return ParticipantVisibilityState.classVisible;
  }
}

InterventionState _interventionFromString(String? value) {
  switch (value) {
    case 'nudged':
      return InterventionState.nudged;
    case 'tutorObserving':
      return InterventionState.tutorObserving;
    case 'tutorIntervening':
      return InterventionState.tutorIntervening;
    case 'correctionSent':
      return InterventionState.correctionSent;
    case 'none':
    default:
      return InterventionState.none;
  }
}

ClassroomEventType _eventTypeFromString(String? value) {
  switch (value) {
    case 'MODE_CHANGED':
      return ClassroomEventType.modeChanged;
    case 'FOCUS_CHANGED':
      return ClassroomEventType.focusChanged;
    case 'TASK_STARTED':
      return ClassroomEventType.taskStarted;
    case 'TASK_COLLECTED':
      return ClassroomEventType.taskCollected;
    case 'SPOTLIGHT_STARTED':
      return ClassroomEventType.spotlightStarted;
    case 'SPOTLIGHT_ENDED':
      return ClassroomEventType.spotlightEnded;
    case 'STUDENT_BOARD_BROADCAST':
      return ClassroomEventType.studentBoardBroadcast;
    case 'RETURN_TO_CLASS':
      return ClassroomEventType.returnToClass;
    case 'SESSION_ENDED':
      return ClassroomEventType.sessionEnded;
    default:
      return ClassroomEventType.unknown;
  }
}
