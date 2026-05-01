import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SeshCreditException implements Exception {
  final String code;
  final String message;

  const SeshCreditException(this.code, this.message);

  @override
  String toString() => message;
}

class SeshCreditBundle {
  final int credits;
  final bool popular;

  const SeshCreditBundle({
    required this.credits,
    this.popular = false,
  });

  double get amountZar => credits * SeshCreditService.creditPriceZar;
}

class SeshCreditService {
  static const double creditPriceZar = 2.0;
  static const int welcomeCredits = 3;
  static const List<SeshCreditBundle> bundles = [
    SeshCreditBundle(credits: 5),
    SeshCreditBundle(credits: 15, popular: true),
    SeshCreditBundle(credits: 30),
  ];

  SeshCreditService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  int balanceFrom(Map<String, dynamic>? data) {
    final rawBalance = data?['seshCreditBalance'];
    if (rawBalance == null) return welcomeCredits;
    return (rawBalance as num).toInt();
  }

  Future<int> ensureBootstrap() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const SeshCreditException('auth_required', 'Sign in to use SeshCredit.');
    }
    try {
      final result = await _functions
          .httpsCallable('ensureSeshCreditBootstrap')
          .call(<String, dynamic>{});
      final payload = result.data;
      if (payload is Map && payload['balance'] is num) {
        return (payload['balance'] as num).toInt();
      }
    } on FirebaseFunctionsException catch (error) {
      throw SeshCreditException(
        error.code,
        error.message ?? 'Failed to prepare SeshCredit.',
      );
    }
    final snapshot = await _userRef(user.uid).get();
    return balanceFrom(snapshot.data());
  }

  Future<int> fetchBalance() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const SeshCreditException('auth_required', 'Sign in to use SeshCredit.');
    }

    final snapshot = await _userRef(user.uid).get();
    return balanceFrom(snapshot.data());
  }

  Future<int> purchaseCredits({
    required int credits,
    String source = 'store',
  }) async {
    if (credits <= 0) {
      throw const SeshCreditException('invalid_bundle', 'Credits must be greater than zero.');
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw const SeshCreditException('auth_required', 'Sign in to buy SeshCredit.');
    }

    try {
      final result = await _functions
          .httpsCallable('purchaseSeshCredits')
          .call(<String, dynamic>{
            'credits': credits,
            'source': source,
          });
      final payload = result.data;
      if (payload is Map && payload['balance'] is num) {
        return (payload['balance'] as num).toInt();
      }
      throw const SeshCreditException(
        'purchase_failed',
        'SeshCredit purchase did not complete.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SeshCreditException(
        error.code,
        error.message ?? 'SeshCredit purchase failed.',
      );
    }
  }

  Future<int> unlockLectureCapture({
    required String folderId,
    required String noteId,
    required String noteTitle,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const SeshCreditException('auth_required', 'Sign in to unlock lecture capture.');
    }

    try {
      final result = await _functions
          .httpsCallable('unlockLectureCapture')
          .call(<String, dynamic>{
            'folderId': folderId,
            'noteId': noteId,
            'noteTitle': noteTitle,
          });
      final payload = result.data;
      if (payload is Map && payload['balance'] is num) {
        return (payload['balance'] as num).toInt();
      }
      throw const SeshCreditException(
        'unlock_failed',
        'Lecture capture unlock did not complete.',
      );
    } on FirebaseFunctionsException catch (error) {
      throw SeshCreditException(
        error.code,
        error.message ?? 'Lecture capture unlock failed.',
      );
    }
  }
}
