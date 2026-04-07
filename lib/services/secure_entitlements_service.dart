import 'package:cloud_functions/cloud_functions.dart';

class SecureEntitlementException implements Exception {
  const SecureEntitlementException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SecureEntitlementException($code): $message';
}

class SeshFocusStatus {
  const SeshFocusStatus({
    required this.freeFocusPasses,
    required this.focusEmergencyPasses,
    required this.seshMinutes,
    required this.xp,
  });

  final int freeFocusPasses;
  final int focusEmergencyPasses;
  final int seshMinutes;
  final int xp;

  factory SeshFocusStatus.fromMap(Map<Object?, Object?> data) {
    int readInt(String key) => (data[key] as num?)?.toInt() ?? 0;

    return SeshFocusStatus(
      freeFocusPasses: readInt('freeFocusPasses'),
      focusEmergencyPasses: readInt('focusEmergencyPasses'),
      seshMinutes: readInt('seshMinutes'),
      xp: readInt('xp'),
    );
  }
}

class SeshFocusAccessResult {
  const SeshFocusAccessResult({
    required this.resourceUsed,
    required this.resourceType,
    required this.freeFocusPasses,
    required this.seshMinutes,
    required this.xp,
    this.focusSessionId,
  });

  final String resourceUsed;
  final String resourceType;
  final int freeFocusPasses;
  final int seshMinutes;
  final int xp;
  final String? focusSessionId;

  factory SeshFocusAccessResult.fromMap(Map<Object?, Object?> data) {
    int readInt(String key) => (data[key] as num?)?.toInt() ?? 0;

    return SeshFocusAccessResult(
      resourceUsed: (data['resourceUsed'] ?? '').toString(),
      resourceType: (data['resourceType'] ?? '').toString(),
      freeFocusPasses: readInt('freeFocusPasses'),
      seshMinutes: readInt('seshMinutes'),
      xp: readInt('xp'),
      focusSessionId: (data['focusSessionId'] as String?)?.trim().isEmpty ?? true
          ? null
          : (data['focusSessionId'] as String),
    );
  }
}

class StudyVaultPurchaseResult {
  const StudyVaultPurchaseResult({
    required this.alreadyPurchased,
    required this.resourceId,
    required this.priceZar,
  });

  final bool alreadyPurchased;
  final String resourceId;
  final int priceZar;

  factory StudyVaultPurchaseResult.fromMap(Map<Object?, Object?> data) {
    return StudyVaultPurchaseResult(
      alreadyPurchased: data['alreadyPurchased'] == true,
      resourceId: (data['resourceId'] ?? '').toString(),
      priceZar: (data['priceZar'] as num?)?.toInt() ?? 0,
    );
  }
}

class SecureEntitlementsService {
  SecureEntitlementsService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  Future<int> purchaseSeshMinutes({
    required int minutes,
    String source = 'focus_store',
  }) async {
    try {
      final result = await _functions.httpsCallable('purchaseSeshMinutes').call(
        <String, dynamic>{
          'minutes': minutes,
          'source': source,
        },
      );
      final payload = result.data;
      if (payload is Map && payload['minutesBalance'] is num) {
        return (payload['minutesBalance'] as num).toInt();
      }
      throw const SecureEntitlementException(
        'purchase_failed',
        'Sesh Minutes purchase did not complete.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureEntitlementException(
        error.code,
        error.message ?? 'Sesh Minutes purchase failed.',
      );
    }
  }

  Future<SeshFocusStatus> fetchSeshFocusStatus() async {
    try {
      final result = await _functions
          .httpsCallable('getSeshFocusStatus')
          .call(<String, dynamic>{});
      final payload = result.data;
      if (payload is Map<Object?, Object?>) {
        return SeshFocusStatus.fromMap(payload);
      }
      throw const SecureEntitlementException(
        'status_unavailable',
        'SeshFocus status is unavailable.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureEntitlementException(
        error.code,
        error.message ?? 'SeshFocus status failed to load.',
      );
    }
  }

  Future<SeshFocusAccessResult> consumeSeshFocusAccess({
    required int durationMinutes,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('consumeSeshFocusAccess')
          .call(<String, dynamic>{'durationMinutes': durationMinutes});
      final payload = result.data;
      if (payload is Map<Object?, Object?>) {
        return SeshFocusAccessResult.fromMap(payload);
      }
      throw const SecureEntitlementException(
        'focus_start_failed',
        'SeshFocus could not start.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureEntitlementException(
        error.code,
        error.message ?? 'SeshFocus could not start.',
      );
    }
  }

  Future<SeshFocusAccessResult> unlockSeshFocusEarly() async {
    try {
      final result = await _functions
          .httpsCallable('unlockSeshFocusEarly')
          .call(<String, dynamic>{});
      final payload = result.data;
      if (payload is Map<Object?, Object?>) {
        return SeshFocusAccessResult.fromMap(payload);
      }
      throw const SecureEntitlementException(
        'focus_unlock_failed',
        'SeshFocus early unlock failed.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureEntitlementException(
        error.code,
        error.message ?? 'SeshFocus early unlock failed.',
      );
    }
  }

  Future<StudyVaultPurchaseResult> purchaseStudyVaultResource({
    required String resourceId,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('purchaseStudyVaultResource')
          .call(<String, dynamic>{'resourceId': resourceId});
      final payload = result.data;
      if (payload is Map<Object?, Object?>) {
        return StudyVaultPurchaseResult.fromMap(payload);
      }
      throw const SecureEntitlementException(
        'vault_purchase_failed',
        'StudyVault unlock failed.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SecureEntitlementException(
        error.code,
        error.message ?? 'StudyVault unlock failed.',
      );
    }
  }
}
