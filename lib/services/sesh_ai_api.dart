import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class SeshAiApi {
  SeshAiApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _defaultBaseUrl;

  static const String _defaultBaseUrl = String.fromEnvironment(
    'SESH_AI_BASE_URL',
    defaultValue: 'https://sesh-ai-gateway-la27lnskvq-nw.a.run.app',
  );

  final http.Client _client;
  final String baseUrl;
  final _uuid = const Uuid();

  Future<Map<String, dynamic>> chatSocratic({
    required String message,
    String? subject,
    List<String>? attachments,
    String? threadId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Missing auth token');
    }

    final payload = {
      'userId': user.uid,
      'threadId': threadId ?? _uuid.v4(),
      'message': message,
      'context': {
        if (subject != null && subject.isNotEmpty) 'subject': subject,
        if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
      },
    };

    return _postJson('/ai/chat/socratic', token, payload);
  }

  Future<Map<String, dynamic>> notesEnhance({
    required String pdfSignedUrl,
    String? subject,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Missing auth token');
    }

    final payload = {
      'userId': user.uid,
      'pdfSignedUrl': pdfSignedUrl,
      if (subject != null && subject.isNotEmpty) 'subject': subject,
    };

    return _postJson('/ai/notes/enhance', token, payload);
  }

  Future<Map<String, dynamic>> practiceGenerate({
    required String sourceFileSignedUrl,
    String? subject,
    Map<String, int>? difficultyCounts,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Missing auth token');
    }

    final payload = {
      'userId': user.uid,
      'sourceFileSignedUrl': sourceFileSignedUrl,
      if (subject != null && subject.isNotEmpty) 'subject': subject,
      'difficultyCounts': difficultyCounts ??
          {
            'weak': 2,
            'medium': 2,
            'hard': 1,
            'impossible': 0,
          },
    };

    return _postJson('/ai/practice/generate', token, payload);
  }

  Future<Map<String, dynamic>> practiceCoach({
    required String questionId,
    required String questionText,
    required String studentAttemptText,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Missing auth token');
    }

    final payload = {
      'userId': user.uid,
      'questionId': questionId,
      'questionText': questionText,
      'studentAttemptText': studentAttemptText,
    };

    return _postJson('/ai/practice/coach', token, payload);
  }

  Future<Map<String, dynamic>> calendarImportTimetable({
    required String timetablePdfSignedUrl,
    String? termStartDate,
    required String timezone,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Missing auth token');
    }

    final payload = {
      'userId': user.uid,
      'timetablePdfSignedUrl': timetablePdfSignedUrl,
      if (termStartDate != null && termStartDate.isNotEmpty) 'termStartDate': termStartDate,
      'timezone': timezone,
    };

    return _postJson('/ai/calendar/importTimetable', token, payload);
  }

  Future<Map<String, dynamic>> sessionSummarize({
    required String sessionId,
    required List<String> boardSnapshotSignedUrls,
    required List<Map<String, dynamic>> chatLog,
    String? subject,
    required List<Map<String, dynamic>> participants,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw Exception('Missing auth token');
    }

    final payload = {
      'userId': user.uid,
      'sessionId': sessionId,
      'boardSnapshotSignedUrls': boardSnapshotSignedUrls,
      'chatLog': chatLog,
      if (subject != null && subject.isNotEmpty) 'subject': subject,
      'participants': participants,
    };

    return _postJson('/ai/session/summarize', token, payload);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    String token,
    Map<String, dynamic> payload,
  ) async {
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
