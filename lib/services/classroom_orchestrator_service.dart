import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'parallel_practice/local_permissions.dart';

class ClassroomOrchestratorService {
  ClassroomOrchestratorService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required String baseUrl,
    http.Client? client,
  })  : _auth = auth,
        _firestore = firestore,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final String _baseUrl;
  final http.Client _client;
  final Uuid _uuid = const Uuid();

  String newActionId() => _uuid.v4();

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchState(String sessionId) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('sessionState')
        .doc('sessionState')
        .snapshots(includeMetadataChanges: true);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents(String sessionId) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('sessionEvents')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots(includeMetadataChanges: true);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchParticipants(String sessionId) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('participants')
        .snapshots(includeMetadataChanges: true);
  }

  Future<Map<String, dynamic>> teachAll({
    required String sessionId,
    bool classLock = true,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/teachAll', {
      'sessionId': sessionId,
      'classLock': classLock,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> sendClasswork({
    required String sessionId,
    required Map<String, dynamic> taskPayload,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/sendClasswork', {
      'sessionId': sessionId,
      'taskPayload': taskPayload,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> monitorEveryoneQuietly({
    required String sessionId,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/monitor', {
      'sessionId': sessionId,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> focusStudent({
    required String sessionId,
    required String studentId,
    bool observeOnly = false,
    String? reason,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/focusStudent', {
      'sessionId': sessionId,
      'studentId': studentId,
      'observeOnly': observeOnly,
      if (reason != null) 'reason': reason,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> returnToClass({
    required String sessionId,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/returnToClass', {
      'sessionId': sessionId,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> collectTask({
    required String sessionId,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/collectNow', {
      'sessionId': sessionId,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> showStudentBoardToClass({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/showToGroup', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> markAndExplain({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    required String annotationsRef,
    String? voiceNoteRef,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/sendCorrection', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
      'annotationsRef': annotationsRef,
      if (voiceNoteRef != null) 'voiceNoteRef': voiceNoteRef,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> endSessionWithStructuredOutputs({
    required String sessionId,
    Map<String, dynamic>? wrapOptions,
    String? actionId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/classroom/endSession', {
      'sessionId': sessionId,
      if (wrapOptions != null) 'wrapOptions': wrapOptions,
      'actionId': actionId ?? newActionId(),
    });
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken();
    final response = await _client.post(
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
