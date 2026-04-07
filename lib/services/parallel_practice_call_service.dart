import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ParallelPracticeCallService {
  ParallelPracticeCallService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _defaultBaseUrl;

  static const String _defaultBaseUrl = String.fromEnvironment(
    'PARALLEL_PRACTICE_API_BASE_V2',
    defaultValue:
        'https://europe-west2-seshly-9e638.cloudfunctions.net/parallelPracticeV2Api',
  );

  final http.Client _client;
  final String baseUrl;

  Future<Map<String, dynamic>> createSession({
    String? title,
    String? subject,
    int? maxParticipants,
  }) {
    return _post('/session/create', {
      if (title != null) 'title': title,
      if (subject != null) 'subject': subject,
      if (maxParticipants != null) 'maxParticipants': maxParticipants,
    });
  }

  Future<Map<String, dynamic>> joinSession(String sessionId) {
    return _post('/session/join', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> leaveSession(String sessionId) {
    return _post('/session/leave', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> createInvite({
    required String sessionId,
    required String roleToGrant,
    required DateTime expiresAt,
    required int maxUses,
  }) {
    return _post('/session/createInvite', {
      'sessionId': sessionId,
      'roleToGrant': roleToGrant,
      'expiresAt': expiresAt.toIso8601String(),
      'maxUses': maxUses,
    });
  }

  Future<Map<String, dynamic>> redeemInvite({
    required String sessionId,
    required String inviteId,
  }) {
    return _post('/session/redeemInvite', {
      'sessionId': sessionId,
      'inviteId': inviteId,
    });
  }

  Future<Map<String, dynamic>> addTutor({
    required String sessionId,
    String? targetUid,
    String? inviteId,
  }) {
    return _post('/session/addTutor', {
      'sessionId': sessionId,
      if (targetUid != null) 'targetUid': targetUid,
      if (inviteId != null) 'inviteId': inviteId,
    });
  }

  Future<Map<String, dynamic>> setMode(String sessionId, String mode) {
    return _post('/session/setMode', {'sessionId': sessionId, 'mode': mode});
  }

  Future<Map<String, dynamic>> giveTask({
    required String sessionId,
    required Map<String, dynamic> taskPayload,
  }) {
    return _post('/session/giveTask', {
      'sessionId': sessionId,
      'taskPayload': taskPayload,
    });
  }

  Future<Map<String, dynamic>> extendTimer({
    required String sessionId,
    required int deltaSeconds,
  }) {
    return _post('/session/extendTimer', {
      'sessionId': sessionId,
      'deltaSeconds': deltaSeconds,
    });
  }

  Future<Map<String, dynamic>> broadcastHint({
    required String sessionId,
    required String hintText,
    String? aiOutputRef,
  }) {
    return _post('/session/broadcastHint', {
      'sessionId': sessionId,
      'hintText': hintText,
      if (aiOutputRef != null) 'aiOutputRef': aiOutputRef,
    });
  }

  Future<Map<String, dynamic>> collectNow(String sessionId) {
    return _post('/session/collectNow', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> showToGroup({
    required String sessionId,
    required String studentId,
    required String snapshotId,
  }) {
    return _post('/session/showToGroup', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
    });
  }

  Future<Map<String, dynamic>> sendCorrection({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    required String annotationsRef,
    String? voiceNoteRef,
  }) {
    return _post('/session/sendCorrection', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
      'annotationsRef': annotationsRef,
      if (voiceNoteRef != null) 'voiceNoteRef': voiceNoteRef,
    });
  }

  Future<Map<String, dynamic>> markExemplar({
    required String sessionId,
    required String snapshotId,
  }) {
    return _post('/session/markExemplar', {
      'sessionId': sessionId,
      'snapshotId': snapshotId,
    });
  }

  Future<Map<String, dynamic>> endSession({
    required String sessionId,
    Map<String, dynamic>? wrapOptions,
    bool? allowCoTutorEnd,
  }) {
    return _post('/session/end', {
      'sessionId': sessionId,
      if (wrapOptions != null) 'wrapOptions': wrapOptions,
      if (allowCoTutorEnd != null) 'allowCoTutorEnd': allowCoTutorEnd,
    });
  }

  Future<Map<String, dynamic>> getConnectionInfo(String sessionId) {
    return _post('/session/getConnectionInfo', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> mintLiveKitToken(String sessionId) {
    return _post('/session/mintLiveKitToken', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> startRecording(String sessionId) {
    return _post('/session/recording/start', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> stopRecording(String sessionId) {
    return _post('/session/recording/stop', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> sendSignal({
    required String sessionId,
    required String pairId,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    return _post('/p2p/signal', {
      'sessionId': sessionId,
      'pairId': pairId,
      'type': type,
      'payload': payload,
    });
  }

  Future<Map<String, dynamic>> emitLaser({
    required String sessionId,
    required Map<String, dynamic> payload,
  }) {
    return _post('/laser/emit', {
      'sessionId': sessionId,
      'payload': payload,
    });
  }

  Future<Map<String, dynamic>> prepareVoiceNote({
    required String sessionId,
    required String targetType,
    required String targetId,
    int? durationSec,
    String? url,
  }) {
    return _post('/voiceNotes/prepare', {
      'sessionId': sessionId,
      'targetType': targetType,
      'targetId': targetId,
      if (durationSec != null) 'durationSec': durationSec,
      if (url != null) 'url': url,
    });
  }

  Future<Map<String, dynamic>> enqueueAiJob({
    required String sessionId,
    required String type,
    Map<String, dynamic>? payload,
  }) {
    return _post('/ai/enqueue', {
      'sessionId': sessionId,
      'type': type,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>> studentSeshHelp({
    required String sessionId,
    required String taskId,
    String? message,
  }) {
    return _post('/ai/studentSeshHelpRequest', {
      'sessionId': sessionId,
      'taskId': taskId,
      if (message != null) 'message': message,
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSession(String sessionId) {
    return FirebaseFirestore.instance.collection('sessions').doc(sessionId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSessionState(String sessionId) {
    return FirebaseFirestore.instance
        .collection('sessions')
        .doc(sessionId)
        .collection('sessionState')
        .doc('sessionState')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamParticipants(String sessionId) {
    return FirebaseFirestore.instance
        .collection('sessions')
        .doc(sessionId)
        .collection('participants')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamSignaling(String sessionId, String uid) {
    return FirebaseFirestore.instance
        .collection('sessions')
        .doc(sessionId)
        .collection('webrtcSignaling')
        .where('from', isNotEqualTo: uid)
        .orderBy('updatedAt', descending: false)
        .snapshots();
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> payload) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();

    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
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
