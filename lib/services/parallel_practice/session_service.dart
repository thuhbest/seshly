import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';

class SessionService {
  SessionService({required FirebaseAuth auth, required String baseUrl})
      : _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<Map<String, dynamic>> createSession({String? title, String? subject, int? maxParticipants}) {
    return _post('/session/create', {
      if (title != null) 'title': title,
      if (subject != null) 'subject': subject,
      if (maxParticipants != null) 'maxParticipants': maxParticipants,
    });
  }

  Future<Map<String, dynamic>> createInvite({
    required String sessionId,
    required String roleToGrant,
    required DateTime expiresAt,
    required int maxUses,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/createInvite', {
      'sessionId': sessionId,
      'roleToGrant': roleToGrant,
      'expiresAt': expiresAt.toIso8601String(),
      'maxUses': maxUses,
    });
  }

  Future<Map<String, dynamic>> redeemInvite({required String sessionId, required String inviteId}) {
    return _post('/session/redeemInvite', {'sessionId': sessionId, 'inviteId': inviteId});
  }

  Future<Map<String, dynamic>> addTutor({
    required String sessionId,
    String? targetUid,
    String? inviteId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor});
    return _post('/session/addTutor', {
      'sessionId': sessionId,
      if (targetUid != null) 'targetUid': targetUid,
      if (inviteId != null) 'inviteId': inviteId,
    });
  }

  Future<Map<String, dynamic>> promoteTutor({
    required String sessionId,
    required String targetUid,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor});
    return _post('/session/promoteTutor', {'sessionId': sessionId, 'targetUid': targetUid});
  }

  Future<Map<String, dynamic>> setMode({
    required String sessionId,
    required String mode,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor});
    return _post('/session/setMode', {'sessionId': sessionId, 'mode': mode});
  }

  Future<Map<String, dynamic>> endSession({
    required String sessionId,
    Map<String, dynamic>? wrapOptions,
    String? idempotencyKey,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor});
    return _post('/session/end', {
      'sessionId': sessionId,
      if (wrapOptions != null) 'wrapOptions': wrapOptions,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
  }

  Future<Map<String, dynamic>> startRecording(String sessionId) {
    return _post('/session/recording/start', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> stopRecording(String sessionId) {
    return _post('/session/recording/stop', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> joinSession(String sessionId) {
    return _post('/session/join', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> leaveSession(String sessionId) {
    return _post('/session/leave', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> getConnectionInfo(String sessionId) {
    return _post('/session/getConnectionInfo', {'sessionId': sessionId});
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
