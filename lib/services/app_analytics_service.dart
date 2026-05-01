import 'package:firebase_analytics/firebase_analytics.dart';

class AppAnalyticsService {
  AppAnalyticsService._();

  static final AppAnalyticsService instance = AppAnalyticsService._();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  Future<void> setUserId(String? userId) async {
    try {
      await _analytics.setUserId(id: userId);
    } catch (_) {}
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    try {
      await _analytics.logEvent(
        name: name,
        parameters: _sanitizeParameters(parameters),
      );
    } catch (_) {}
  }

  Future<void> trackAuthFlow(
    String action, {
    String status = 'ok',
    bool emailVerified = false,
  }) {
    return logEvent(
      'auth_flow',
      parameters: <String, Object?>{
        'action': action,
        'status': status,
        'email_verified': emailVerified,
      },
    );
  }

  Future<void> trackVerification({
    required String action,
    required String status,
  }) {
    return logEvent(
      'verification_flow',
      parameters: <String, Object?>{
        'action': action,
        'status': status,
      },
    );
  }

  Future<void> trackTutorSearch({
    required String subject,
    required int resultCount,
    bool cached = false,
  }) {
    return logEvent(
      'tutor_search',
      parameters: <String, Object?>{
        'subject': subject,
        'result_count': resultCount,
        'cached': cached,
      },
    );
  }

  Future<void> trackSessionLifecycle({
    required String action,
    required String status,
  }) {
    return logEvent(
      'session_lifecycle',
      parameters: <String, Object?>{
        'action': action,
        'status': status,
      },
    );
  }

  Future<void> trackPayment({
    required String action,
    required String status,
  }) {
    return logEvent(
      'payment_flow',
      parameters: <String, Object?>{
        'action': action,
        'status': status,
      },
    );
  }

  Future<void> trackAiUsage({
    required String action,
    required String status,
  }) {
    return logEvent(
      'ai_usage',
      parameters: <String, Object?>{
        'action': action,
        'status': status,
      },
    );
  }

  Future<void> trackHandledError({
    required String category,
    required String source,
    required String status,
  }) {
    return logEvent(
      'handled_error',
      parameters: <String, Object?>{
        'category': category,
        'source': source,
        'status': status,
      },
    );
  }

  Future<void> trackModeration({
    required String surface,
    required String outcome,
  }) {
    return logEvent(
      'moderation_signal',
      parameters: <String, Object?>{
        'surface': surface,
        'outcome': outcome,
      },
    );
  }

  Map<String, Object> _sanitizeParameters(Map<String, Object?> parameters) {
    final sanitized = <String, Object>{};
    for (final entry in parameters.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is String) {
        sanitized[key] = value.length > 100 ? value.substring(0, 100) : value;
      } else if (value is num || value is bool) {
        sanitized[key] = value;
      }
    }
    return sanitized;
  }
}
