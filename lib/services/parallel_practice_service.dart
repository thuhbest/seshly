import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ParallelPracticeService {
  ParallelPracticeService({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'PARALLEL_PRACTICE_API_BASE',
              defaultValue:
                  'https://europe-west1-seshly-9e638.cloudfunctions.net/parallelPracticeApi',
            ),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> createSession({
    String? title,
    String? subject,
    int? maxParticipants,
    bool? allowCoTutorEnd,
  }) {
    return _post('/session/create', {
      if (title != null) 'title': title,
      if (subject != null) 'subject': subject,
      if (maxParticipants != null) 'maxParticipants': maxParticipants,
      if (allowCoTutorEnd != null) 'allowCoTutorEnd': allowCoTutorEnd,
    });
  }

  Future<Map<String, dynamic>> joinSession(String sessionId) {
    return _post('/session/join', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> leaveSession(String sessionId) {
    return _post('/session/leave', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> endSession(String sessionId) {
    return _post('/session/end', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> setMode(String sessionId, String mode) {
    return _post('/session/mode', {'sessionId': sessionId, 'mode': mode});
  }

  Future<Map<String, dynamic>> addMarker({
    required String sessionId,
    required String markerType,
    required int timestampMs,
    String? boardSnapshotId,
    String? note,
  }) {
    return _post('/session/marker', {
      'sessionId': sessionId,
      'markerType': markerType,
      'timestampMs': timestampMs,
      if (boardSnapshotId != null) 'boardSnapshotId': boardSnapshotId,
      if (note != null) 'note': note,
    });
  }

  Future<Map<String, dynamic>> addSnapshot({
    required String sessionId,
    required String url,
    required String storagePath,
    String? mode,
    String? studentId,
  }) {
    return _post('/session/snapshot', {
      'sessionId': sessionId,
      'url': url,
      'storagePath': storagePath,
      if (mode != null) 'mode': mode,
      if (studentId != null) 'studentId': studentId,
    });
  }

  Future<Map<String, dynamic>> inviteTutor({
    required String sessionId,
    required String invitedUserId,
  }) {
    return _post('/session/inviteTutor', {
      'sessionId': sessionId,
      'invitedUserId': invitedUserId,
    });
  }

  Future<Map<String, dynamic>> acceptInvite(String sessionId) {
    return _post('/session/acceptInvite', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> promoteTutor({
    required String sessionId,
    required String userId,
  }) {
    return _post('/session/promoteTutor', {
      'sessionId': sessionId,
      'userId': userId,
    });
  }

  Future<Map<String, dynamic>> updateStatus({
    required String sessionId,
    String? status,
    int? progress,
  }) {
    return _post('/practice/status', {
      'sessionId': sessionId,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
    });
  }

  Future<Map<String, dynamic>> requestHelp({
    required String sessionId,
    String? message,
  }) {
    return _post('/practice/requestHelp', {
      'sessionId': sessionId,
      if (message != null) 'message': message,
    });
  }

  Future<Map<String, dynamic>> practiceAction({
    required String sessionId,
    required String action,
    Map<String, dynamic>? payload,
  }) {
    return _post('/practice/action', {
      'sessionId': sessionId,
      'action': action,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>> createTask({
    required String sessionId,
    required String prompt,
    List<String>? attachments,
    int? timerSec,
    String? submissionFormat,
    bool? allowSeshHelp,
    String? rubric,
    String? expectedSolution,
  }) {
    return _post('/task/create', {
      'sessionId': sessionId,
      'prompt': prompt,
      if (attachments != null) 'attachments': attachments,
      if (timerSec != null) 'timerSec': timerSec,
      if (submissionFormat != null) 'submissionFormat': submissionFormat,
      if (allowSeshHelp != null) 'allowSeshHelp': allowSeshHelp,
      if (rubric != null) 'rubric': rubric,
      if (expectedSolution != null) 'expectedSolution': expectedSolution,
    });
  }

  Future<Map<String, dynamic>> submitTask({
    required String sessionId,
    required String taskId,
    String? responseText,
    String? snapshotUrl,
    String? snapshotPath,
  }) {
    return _post('/task/submit', {
      'sessionId': sessionId,
      'taskId': taskId,
      if (responseText != null) 'responseText': responseText,
      if (snapshotUrl != null) 'snapshotUrl': snapshotUrl,
      if (snapshotPath != null) 'snapshotPath': snapshotPath,
    });
  }

  Future<Map<String, dynamic>> saveTemplate({
    required String sessionId,
    required String title,
    required String prompt,
    List<String>? attachments,
    String? rubric,
    String? expectedSolution,
  }) {
    return _post('/task/template/save', {
      'sessionId': sessionId,
      'title': title,
      'prompt': prompt,
      if (attachments != null) 'attachments': attachments,
      if (rubric != null) 'rubric': rubric,
      if (expectedSolution != null) 'expectedSolution': expectedSolution,
    });
  }

  Future<Map<String, dynamic>> listTemplates(String sessionId) {
    return _post('/task/template/list', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> quickAction({
    required String sessionId,
    required String actionType,
    Map<String, dynamic>? payload,
  }) {
    return _post('/session/quickAction', {
      'sessionId': sessionId,
      'actionType': actionType,
      if (payload != null) 'payload': payload,
    });
  }

  Future<Map<String, dynamic>> startRecording(String sessionId) {
    return _post('/session/recording/start', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> stopRecording(String sessionId) {
    return _post('/session/recording/stop', {'sessionId': sessionId});
  }

  Future<Map<String, dynamic>> getLiveKitToken(String sessionId) {
    return _post('/session/token', {'sessionId': sessionId});
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
