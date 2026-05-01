import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'paths.dart';

class RetryBackoff {
  const RetryBackoff._();

  static Duration forAttempt(int attempt) {
    final clamped = attempt < 0 ? 0 : (attempt > 5 ? 5 : attempt);
    const scheduleMs = [1000, 2000, 4000, 8000, 12000, 20000];
    return Duration(milliseconds: scheduleMs[clamped]);
  }
}

class ReliabilityMetricsSnapshot {
  const ReliabilityMetricsSnapshot({
    required this.activeParticipantCount,
    required this.activeTutorCount,
    required this.weakConnectionCount,
    required this.tutorPresenceState,
    required this.studentsMayContinue,
    required this.recommendedMediaProfile,
    required this.callMode,
    required this.callModeVersion,
    required this.recoveryVersion,
    required this.updatedAt,
  });

  final int activeParticipantCount;
  final int activeTutorCount;
  final int weakConnectionCount;
  final String tutorPresenceState;
  final bool studentsMayContinue;
  final String recommendedMediaProfile;
  final String callMode;
  final int callModeVersion;
  final int recoveryVersion;
  final DateTime? updatedAt;

  factory ReliabilityMetricsSnapshot.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ReliabilityMetricsSnapshot(
      activeParticipantCount: _asInt(data['activeParticipantCount']),
      activeTutorCount: _asInt(data['activeTutorCount']),
      weakConnectionCount: _asInt(data['weakConnectionCount']),
      tutorPresenceState: _asString(data['tutorPresenceState']) ?? 'active',
      studentsMayContinue: data['studentsMayContinue'] == true,
      recommendedMediaProfile: _asString(data['recommendedMediaProfile']) ?? 'full',
      callMode: _asString(data['callMode']) ?? 'p2p',
      callModeVersion: _asInt(data['callModeVersion'], fallback: 1),
      recoveryVersion: _asInt(data['recoveryVersion'], fallback: 1),
      updatedAt: _asDateTime(data['updatedAt']),
    );
  }

  static const empty = ReliabilityMetricsSnapshot(
    activeParticipantCount: 0,
    activeTutorCount: 0,
    weakConnectionCount: 0,
    tutorPresenceState: 'active',
    studentsMayContinue: false,
    recommendedMediaProfile: 'full',
    callMode: 'p2p',
    callModeVersion: 1,
    recoveryVersion: 1,
    updatedAt: null,
  );
}

class RecoverySnapshot {
  const RecoverySnapshot({
    required this.serverNowMs,
    required this.connectionInfo,
    required this.classroomState,
    required this.participantState,
    required this.activeTask,
    required this.submissionState,
    required this.boardRecovery,
  });

  final int serverNowMs;
  final Map<String, dynamic> connectionInfo;
  final Map<String, dynamic> classroomState;
  final Map<String, dynamic> participantState;
  final Map<String, dynamic>? activeTask;
  final Map<String, dynamic>? submissionState;
  final Map<String, dynamic> boardRecovery;

  factory RecoverySnapshot.fromPayload(Map<String, dynamic> payload) {
    final data = _asMap(payload['recoverySnapshot']).isNotEmpty
        ? _asMap(payload['recoverySnapshot'])
        : payload;
    return RecoverySnapshot(
      serverNowMs: _asInt(data['serverNowMs']),
      connectionInfo: _asMap(data['connectionInfo']),
      classroomState: _asMap(data['classroomState']),
      participantState: _asMap(data['participantState']),
      activeTask: _nullableMap(data['activeTask']),
      submissionState: _nullableMap(data['submissionState']),
      boardRecovery: _asMap(data['boardRecovery']),
    );
  }
}

class ClassroomReliabilityService {
  ClassroomReliabilityService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required String baseUrl,
  })  : _auth = auth,
        _firestore = firestore,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final String _baseUrl;

  Stream<ReliabilityMetricsSnapshot> watchMetrics(String sessionId) {
    return _firestore
        .collection(Paths.sessions)
        .doc(sessionId)
        .collection(Paths.reliabilityMetrics)
        .doc('current')
        .snapshots()
        .map(ReliabilityMetricsSnapshot.fromDoc);
  }

  Future<Map<String, dynamic>> heartbeat({
    required String sessionId,
    int heartbeatSeq = 0,
    String presenceState = 'online',
    String networkQuality = 'unknown',
    String mediaHealth = 'stable',
    String? preferredMediaProfile,
    String? transportState,
    int callModeVersion = 0,
    bool isReconnect = false,
  }) {
    return _post('/session/heartbeat', {
      'sessionId': sessionId,
      'heartbeatSeq': heartbeatSeq,
      'presenceState': presenceState,
      'networkQuality': networkQuality,
      'mediaHealth': mediaHealth,
      'callModeVersion': callModeVersion,
      'isReconnect': isReconnect,
      if (preferredMediaProfile != null && preferredMediaProfile.trim().isNotEmpty)
        'preferredMediaProfile': preferredMediaProfile.trim(),
      if (transportState != null && transportState.trim().isNotEmpty)
        'transportState': transportState.trim(),
    });
  }

  Future<RecoverySnapshot> recoverState({
    required String sessionId,
    String networkQuality = 'unknown',
    String mediaHealth = 'stable',
    bool forceRejoin = false,
  }) async {
    final payload = await _post('/session/recoverState', {
      'sessionId': sessionId,
      'networkQuality': networkQuality,
      'mediaHealth': mediaHealth,
      'forceRejoin': forceRejoin,
    });
    return RecoverySnapshot.fromPayload(payload);
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

String? _asString(Object? value) => value is String ? value.trim() : null;

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _asDateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

Map<String, dynamic>? _nullableMap(Object? value) {
  final map = _asMap(value);
  return map.isEmpty ? null : map;
}
