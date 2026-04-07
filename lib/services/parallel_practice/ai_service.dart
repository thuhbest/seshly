import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';

class AiService {
  AiService({required FirebaseAuth auth, required String baseUrl, required FirebaseFirestore firestore})
      : _auth = auth,
        _baseUrl = baseUrl,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final String _baseUrl;
  final FirebaseFirestore _firestore;

  Future<Map<String, dynamic>> enqueueJob({
    required String sessionId,
    required String type,
    Map<String, dynamic>? payload,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/ai/enqueue', {
      'sessionId': sessionId,
      'type': type,
      if (payload != null) 'payload': payload,
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchJob({
    required String sessionId,
    required String jobId,
  }) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('aiJobs')
        .doc(jobId)
        .snapshots(includeMetadataChanges: true);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOutputs(String sessionId) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('aiOutputs')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true);
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
