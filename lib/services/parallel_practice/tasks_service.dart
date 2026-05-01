import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';

class TasksService {
  TasksService({required FirebaseAuth auth, required String baseUrl})
      : _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<Map<String, dynamic>> giveTask({
    required String sessionId,
    required Map<String, dynamic> taskPayload,
    String? idempotencyKey,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/giveTask', {
      'sessionId': sessionId,
      'taskPayload': taskPayload,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
  }

  Future<Map<String, dynamic>> extendTimer({
    required String sessionId,
    required int deltaSeconds,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/extendTimer', {
      'sessionId': sessionId,
      'deltaSeconds': deltaSeconds,
    });
  }

  Future<Map<String, dynamic>> broadcastHint({
    required String sessionId,
    required String hintText,
    String? aiOutputRef,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/broadcastHint', {
      'sessionId': sessionId,
      'hintText': hintText,
      if (aiOutputRef != null) 'aiOutputRef': aiOutputRef,
    });
  }

  Future<Map<String, dynamic>> collectNow({required String sessionId, required SessionRole role}) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/collectNow', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> submitTask({
    required String sessionId,
    required String taskId,
    String? responseText,
    String? snapshotRef,
    String? idempotencyKey,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.student});
    return _post('/task/submit', {
      'sessionId': sessionId,
      'taskId': taskId,
      if (responseText != null) 'responseText': responseText,
      if (snapshotRef != null) 'snapshotRef': snapshotRef,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    });
  }

  Future<Map<String, dynamic>> requestHelp({
    required String sessionId,
    required String taskId,
    String? message,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.student});
    return _post('/ai/studentSeshHelpRequest', {
      'sessionId': sessionId,
      'taskId': taskId,
      if (message != null) 'message': message,
    });
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
