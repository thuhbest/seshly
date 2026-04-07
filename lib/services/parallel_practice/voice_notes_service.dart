import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';

class VoiceNotesService {
  VoiceNotesService({required FirebaseAuth auth, required String baseUrl})
      : _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<Map<String, dynamic>> prepareVoiceNote({
    required String sessionId,
    required String targetType,
    required String targetId,
    int? durationSec,
    String? url,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/voiceNotes/prepare', {
      'sessionId': sessionId,
      'targetType': targetType,
      'targetId': targetId,
      if (durationSec != null) 'durationSec': durationSec,
      if (url != null) 'url': url,
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
