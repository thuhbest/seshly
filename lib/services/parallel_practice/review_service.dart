import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';

class ReviewService {
  ReviewService({required FirebaseAuth auth, required String baseUrl})
      : _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<Map<String, dynamic>> tagStudent({
    required String sessionId,
    required String studentId,
    required String taskId,
    required String tag,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/review/tag', {
      'sessionId': sessionId,
      'studentId': studentId,
      'taskId': taskId,
      'tag': tag,
    });
  }

  Future<Map<String, dynamic>> showToGroup({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
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
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
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
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/session/markExemplar', {
      'sessionId': sessionId,
      'snapshotId': snapshotId,
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
