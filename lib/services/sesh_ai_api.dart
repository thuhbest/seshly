import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class SeshAiApiException implements Exception {
  const SeshAiApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.retryable = false,
  });

  final String code;
  final String message;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() => 'SeshAiApiException($code): $message';
}

class SeshAiApi {
  SeshAiApi({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl);

  static const String _defaultBaseUrl = String.fromEnvironment(
    'SESH_AI_BASE_URL',
    defaultValue: 'https://sesh-ai-gateway-la27lnskvq-nw.a.run.app',
  );

  final http.Client _client;
  final String baseUrl;
  final _uuid = const Uuid();

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw StateError(
        'Sesh AI base URL is empty. Pass --dart-define=SESH_AI_BASE_URL=https://your-service.',
      );
    }

    final normalized =
        trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError(
        'Invalid Sesh AI base URL "$value". Expected a full URL like https://example.com.',
      );
    }

    return normalized;
  }

  Future<bool> healthCheck() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

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
    const maxRetries = 2;
    var attempt = 0;

    while (true) {
      attempt += 1;
      try {
        final uri = Uri.parse('$baseUrl$path');
        final response = await _client.post(
          uri,
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }

        final apiError = _buildApiException(response);

        final isRetriable = response.statusCode == 429 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504;
        if (!isRetriable || attempt > maxRetries) {
          throw apiError;
        }

        final retryAfterHeader = response.headers['retry-after'];
        final retryAfterSeconds = retryAfterHeader == null ? null : int.tryParse(retryAfterHeader);
        final baseDelayMs = retryAfterSeconds != null ? retryAfterSeconds * 1000 : 400 * attempt;
        final jitterMs = (baseDelayMs * 0.25).round();
        await Future.delayed(Duration(milliseconds: baseDelayMs + jitterMs));
      } on SocketException {
        if (attempt > maxRetries) {
          throw SeshAiApiException(
            code: 'network_unavailable',
            message: 'Network error. Check your connection and try again.',
            retryable: true,
          );
        }
        final backoffMs = 400 * attempt;
        await Future.delayed(Duration(milliseconds: backoffMs));
      } on HttpException catch (error) {
        if (attempt > maxRetries) {
          throw SeshAiApiException(
            code: 'http_error',
            message: error.message.isEmpty
                ? 'Sesh AI is unavailable right now.'
                : error.message,
            retryable: true,
          );
        }
        final backoffMs = 400 * attempt;
        await Future.delayed(Duration(milliseconds: backoffMs));
      } on http.ClientException catch (error) {
        if (attempt > maxRetries) {
          throw SeshAiApiException(
            code: 'client_error',
            message: error.message.isEmpty
                ? 'Sesh AI is unavailable right now.'
                : error.message,
            retryable: true,
          );
        }
        final backoffMs = 400 * attempt;
        await Future.delayed(Duration(milliseconds: backoffMs));
      } on SeshAiApiException {
        rethrow;
      } catch (error) {
        if (attempt > maxRetries) {
          throw SeshAiApiException(
            code: 'unknown',
            message: 'Sesh AI is unavailable right now.',
            retryable: true,
          );
        }
        final backoffMs = 400 * attempt;
        await Future.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  SeshAiApiException _buildApiException(http.Response response) {
    String code = 'request_failed';
    String message = 'Sesh AI is unavailable right now.';
    var retryable = false;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        final payload = Map<String, dynamic>.from(decoded);
        final rawCode = payload['error']?.toString().trim();
        final rawMessage = payload['message']?.toString().trim();
        if (rawCode != null && rawCode.isNotEmpty) {
          code = rawCode;
        }
        if (rawMessage != null && rawMessage.isNotEmpty) {
          message = rawMessage;
        }
        retryable = payload['retryable'] == true;
      }
    } catch (_) {}

    return SeshAiApiException(
      code: code,
      message: message,
      statusCode: response.statusCode,
      retryable: retryable || response.statusCode >= 500 || response.statusCode == 429,
    );
  }
}
