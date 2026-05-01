import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'tutoring_backend_service.dart';

String? _asIsoString(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }
  return value.toString();
}

class TutorPayoutHistoryItem {
  const TutorPayoutHistoryItem({
    required this.payoutId,
    required this.payoutWeekKey,
    required this.status,
    required this.providerStatus,
    required this.amountZar,
    required this.currency,
    required this.payoutKind,
    required this.failureReason,
    required this.requestedAtIso,
    required this.paidAtIso,
    required this.failedAtIso,
  });

  final String payoutId;
  final String? payoutWeekKey;
  final String status;
  final String providerStatus;
  final double amountZar;
  final String currency;
  final String? payoutKind;
  final String? failureReason;
  final String? requestedAtIso;
  final String? paidAtIso;
  final String? failedAtIso;

  factory TutorPayoutHistoryItem.fromMap(Map<String, dynamic> map) {
    return TutorPayoutHistoryItem(
      payoutId: (map['payoutId'] ?? '').toString(),
      payoutWeekKey: map['payoutWeekKey']?.toString(),
      status: (map['status'] ?? '').toString(),
      providerStatus: (map['providerStatus'] ?? '').toString(),
      amountZar: (map['amountZar'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] ?? 'ZAR').toString(),
      payoutKind: map['payoutKind']?.toString(),
      failureReason: map['failureReason']?.toString(),
      requestedAtIso: map['requestedAt']?.toString(),
      paidAtIso: map['paidAt']?.toString(),
      failedAtIso: map['failedAt']?.toString(),
    );
  }
}

class TutorFailedPayoutNotice {
  const TutorFailedPayoutNotice({
    required this.payoutId,
    required this.payoutWeekKey,
    required this.amountZar,
    required this.currency,
    required this.failureReason,
    required this.failedAtIso,
  });

  final String payoutId;
  final String? payoutWeekKey;
  final double amountZar;
  final String currency;
  final String? failureReason;
  final String? failedAtIso;

  factory TutorFailedPayoutNotice.fromMap(Map<String, dynamic> map) {
    return TutorFailedPayoutNotice(
      payoutId: (map['payoutId'] ?? '').toString(),
      payoutWeekKey: map['payoutWeekKey']?.toString(),
      amountZar: (map['amountZar'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] ?? 'ZAR').toString(),
      failureReason: map['failureReason']?.toString(),
      failedAtIso: map['failedAt']?.toString(),
    );
  }
}

class TutorPayoutDashboardData {
  const TutorPayoutDashboardData({
    required this.tutorId,
    required this.currency,
    required this.onboardingStatus,
    required this.payoutEnabled,
    required this.payoutMode,
    required this.payoutProfileId,
    required this.payoutProfileVerificationStatus,
    required this.payoutProfileBankName,
    required this.payoutProfileAccountNumberMasked,
    required this.availableNextPayoutAmountZar,
    required this.pendingWeeklyAmountZar,
    required this.blockedPayoutReasonCode,
    required this.blockedPayoutReasonMessage,
    required this.nextPayoutDateKey,
    required this.nextPayoutDisplayLabel,
    required this.nextPayoutLocalTime,
    required this.failedPayoutNoticeCount,
    required this.hasFailedPayoutNotices,
    required this.availableBalanceZar,
    required this.reservedForPayoutZar,
    required this.heldForDisputesZar,
    required this.lifetimePaidOutZar,
    required this.lastPayoutAtIso,
    required this.payoutHistoryPreview,
    required this.failedPayoutNotices,
    required this.updatedAtIso,
  });

  final String tutorId;
  final String currency;
  final String onboardingStatus;
  final bool payoutEnabled;
  final String payoutMode;
  final String? payoutProfileId;
  final String payoutProfileVerificationStatus;
  final String? payoutProfileBankName;
  final String? payoutProfileAccountNumberMasked;
  final double availableNextPayoutAmountZar;
  final double pendingWeeklyAmountZar;
  final String? blockedPayoutReasonCode;
  final String? blockedPayoutReasonMessage;
  final String? nextPayoutDateKey;
  final String? nextPayoutDisplayLabel;
  final String? nextPayoutLocalTime;
  final int failedPayoutNoticeCount;
  final bool hasFailedPayoutNotices;
  final double availableBalanceZar;
  final double reservedForPayoutZar;
  final double heldForDisputesZar;
  final double lifetimePaidOutZar;
  final String? lastPayoutAtIso;
  final List<TutorPayoutHistoryItem> payoutHistoryPreview;
  final List<TutorFailedPayoutNotice> failedPayoutNotices;
  final String? updatedAtIso;

  factory TutorPayoutDashboardData.fromMap(Map<String, dynamic> map) {
    final history =
        (map['payoutHistoryPreview'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((entry) => TutorPayoutHistoryItem.fromMap(Map<String, dynamic>.from(entry)))
            .toList();
    final failed =
        (map['failedPayoutNotices'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((entry) => TutorFailedPayoutNotice.fromMap(Map<String, dynamic>.from(entry)))
            .toList();

    return TutorPayoutDashboardData(
      tutorId: (map['tutorId'] ?? '').toString(),
      currency: (map['currency'] ?? 'ZAR').toString(),
      onboardingStatus: (map['onboardingStatus'] ?? 'not_started').toString(),
      payoutEnabled: map['payoutEnabled'] == true,
      payoutMode: (map['payoutMode'] ?? 'MANUAL').toString(),
      payoutProfileId: map['payoutProfileId']?.toString(),
      payoutProfileVerificationStatus:
          (map['payoutProfileVerificationStatus'] ?? 'not_started').toString(),
      payoutProfileBankName: map['payoutProfileBankName']?.toString(),
      payoutProfileAccountNumberMasked:
          map['payoutProfileAccountNumberMasked']?.toString(),
      availableNextPayoutAmountZar:
          (map['availableNextPayoutAmountZar'] as num?)?.toDouble() ?? 0,
      pendingWeeklyAmountZar:
          (map['pendingWeeklyAmountZar'] as num?)?.toDouble() ?? 0,
      blockedPayoutReasonCode: map['blockedPayoutReasonCode']?.toString(),
      blockedPayoutReasonMessage:
          map['blockedPayoutReasonMessage']?.toString(),
      nextPayoutDateKey: map['nextPayoutDateKey']?.toString(),
      nextPayoutDisplayLabel: map['nextPayoutDisplayLabel']?.toString(),
      nextPayoutLocalTime: map['nextPayoutLocalTime']?.toString(),
      failedPayoutNoticeCount:
          (map['failedPayoutNoticeCount'] as num?)?.toInt() ?? 0,
      hasFailedPayoutNotices: map['hasFailedPayoutNotices'] == true,
      availableBalanceZar:
          (map['availableBalanceZar'] as num?)?.toDouble() ?? 0,
      reservedForPayoutZar:
          (map['reservedForPayoutZar'] as num?)?.toDouble() ?? 0,
      heldForDisputesZar:
          (map['heldForDisputesZar'] as num?)?.toDouble() ?? 0,
      lifetimePaidOutZar:
          (map['lifetimePaidOutZar'] as num?)?.toDouble() ?? 0,
      lastPayoutAtIso: _asIsoString(map['lastPayoutAt']),
      payoutHistoryPreview: history,
      failedPayoutNotices: failed,
      updatedAtIso: _asIsoString(map['updatedAt']),
    );
  }
}

class TutorPayoutDashboardService {
  TutorPayoutDashboardService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    TutoringBackendService? backend,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _backend = backend ?? TutoringBackendService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final TutoringBackendService _backend;

  Stream<TutorPayoutDashboardData?> watchCurrentTutorDashboard() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream<TutorPayoutDashboardData?>.empty();
    }
    return _firestore
        .collection('tutor_payout_dashboards')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) {
            return null;
          }
          return TutorPayoutDashboardData.fromMap(data);
        });
  }

  Future<TutorPayoutDashboardData> fetchCurrentTutorDashboard() async {
    final payload = await _backend.getTutorPayoutDashboard();
    return TutorPayoutDashboardData.fromMap(payload);
  }

  Future<List<TutorPayoutHistoryItem>> fetchTutorPayoutHistory({
    int limit = 20,
  }) async {
    final payload = await _backend.listTutorPayoutHistory(limit: limit);
    final items = payload['items'] as List<dynamic>? ?? const <dynamic>[];
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (entry) => TutorPayoutHistoryItem.fromMap(
            Map<String, dynamic>.from(entry),
          ),
        )
        .toList();
  }
}
