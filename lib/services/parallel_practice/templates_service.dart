import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';

class TemplatesService {
  TemplatesService({required FirebaseAuth auth, required String baseUrl})
      : _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Future<Map<String, dynamic>> createTemplate({
    required String title,
    required String task,
    String? rubric,
    String? expectedSolution,
    List<String>? tags,
    List<String>? checklist,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/templates/create', {
      'title': title,
      'task': task,
      if (rubric != null) 'rubric': rubric,
      if (expectedSolution != null) 'expectedSolution': expectedSolution,
      if (tags != null) 'tags': tags,
      if (checklist != null) 'checklist': checklist,
    });
  }

  Future<Map<String, dynamic>> listTemplates({required SessionRole role}) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/templates/list', {});
  }

  Future<Map<String, dynamic>> updateTemplate({
    required String templateId,
    String? title,
    String? task,
    String? rubric,
    String? expectedSolution,
    List<String>? tags,
    List<String>? checklist,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/templates/update', {
      'templateId': templateId,
      if (title != null) 'title': title,
      if (task != null) 'task': task,
      if (rubric != null) 'rubric': rubric,
      if (expectedSolution != null) 'expectedSolution': expectedSolution,
      if (tags != null) 'tags': tags,
      if (checklist != null) 'checklist': checklist,
    });
  }

  Future<Map<String, dynamic>> deleteTemplate({
    required String templateId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/templates/delete', {'templateId': templateId});
  }

  Future<Map<String, dynamic>> applyTemplate({
    required String sessionId,
    required String templateId,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/templates/apply', {
      'sessionId': sessionId,
      'templateId': templateId,
    });
  }

  Future<Map<String, dynamic>> saveTemplateFromTask({
    required String sessionId,
    required String taskId,
    required String title,
    required SessionRole role,
  }) {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    return _post('/templates/saveFromTask', {
      'sessionId': sessionId,
      'taskId': taskId,
      'title': title,
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
