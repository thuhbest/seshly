import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'app_analytics_service.dart';
import 'app_error_service.dart';
import 'community_backend_service.dart';

enum AuthFlowErrorCode {
  wrongPassword,
  userNotFound,
  invalidEmail,
  tooManyRequests,
  networkRequestFailed,
  unavailable,
  verificationRequired,
  partialPostLoginSyncFailure,
  unknown,
}

enum VerificationEmailDispatchStatus { sent, cooldown, alreadyVerified }

class AuthFlowException implements Exception {
  const AuthFlowException({
    required this.code,
    required this.userMessage,
    this.debugMessage,
    this.cause,
  });

  final AuthFlowErrorCode code;
  final String userMessage;
  final String? debugMessage;
  final Object? cause;

  @override
  String toString() => 'AuthFlowException($code, $userMessage)';
}

class VerificationEmailDispatchResult {
  const VerificationEmailDispatchResult({
    required this.status,
    required this.userMessage,
  });

  final VerificationEmailDispatchStatus status;
  final String userMessage;

  bool get sent => status == VerificationEmailDispatchStatus.sent;
}

class AuthSignInResult {
  const AuthSignInResult({
    required this.credential,
    required this.user,
    required this.emailVerified,
    required this.verificationEmailSent,
  });

  final UserCredential credential;
  final User user;
  final bool emailVerified;
  final bool verificationEmailSent;

  bool get requiresVerification => !emailVerified;
}

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  final CommunityBackendService _communityBackend =
      CommunityBackendService.instance;

  static final Map<String, DateTime> _lastVerificationEmailAtByUser =
      <String, DateTime>{};
  static Future<void>? _webPersistenceConfigurationFuture;

  static Future<void> ensureWebPersistenceConfigured() {
    if (!kIsWeb) {
      return Future.value();
    }
    return _webPersistenceConfigurationFuture ??=
        _configureWebPersistenceInternal();
  }

  static Future<void> _configureWebPersistenceInternal() async {
    final traceId =
        'web-persistence-${DateTime.now().microsecondsSinceEpoch}';
    debugPrint(
      '[auth][web_persistence_start] trace=$traceId blocking=true',
    );

    late final FirebaseAuth auth;
    try {
      auth = FirebaseAuth.instance;
    } catch (error, stackTrace) {
      debugPrint(
        '[auth][web_persistence_unavailable] trace=$traceId error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return;
    }

    final attempts = <(Persistence, String)>[
      (Persistence.LOCAL, 'browser_local'),
      (Persistence.SESSION, 'browser_session'),
      (Persistence.NONE, 'memory_only'),
    ];

    for (final attempt in attempts) {
      final persistence = attempt.$1;
      final label = attempt.$2;
      try {
        await auth.setPersistence(persistence);
        debugPrint(
          '[auth][web_persistence_success] trace=$traceId mode=$label',
        );
        return;
      } catch (error, stackTrace) {
        debugPrint(
          '[auth][web_persistence_failure] trace=$traceId mode=$label error=$error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    debugPrint(
      '[auth][web_persistence_skipped] trace=$traceId mode=default_sdk',
    );
  }

  String _newTraceId(String label) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$label-$timestamp';
  }

  void _logAuthEvent(
    String event, {
    String? traceId,
    String? uid,
    bool? emailVerified,
    bool? blocking,
    Object? error,
  }) {
    debugPrint(
      '[auth][$event] trace=${traceId ?? 'n/a'} uid=${uid ?? 'n/a'} '
      'emailVerified=${emailVerified ?? 'n/a'} '
      'blocking=${blocking ?? 'n/a'} '
      '${error != null ? 'error=$error' : ''}',
    );
  }

  AuthFlowException _mapAuthException(
    FirebaseAuthException error, {
    String? debugMessage,
  }) {
    switch (error.code) {
      case 'wrong-password':
        return AuthFlowException(
          code: AuthFlowErrorCode.wrongPassword,
          userMessage: 'Incorrect password. Please try again.',
          debugMessage: debugMessage,
          cause: error,
        );
      case 'user-not-found':
        return AuthFlowException(
          code: AuthFlowErrorCode.userNotFound,
          userMessage:
              'No account found with this email. Please check or sign up.',
          debugMessage: debugMessage,
          cause: error,
        );
      case 'invalid-email':
        return AuthFlowException(
          code: AuthFlowErrorCode.invalidEmail,
          userMessage:
              'Please enter a valid email address (e.g., name@university.ac.za).',
          debugMessage: debugMessage,
          cause: error,
        );
      case 'too-many-requests':
        return AuthFlowException(
          code: AuthFlowErrorCode.tooManyRequests,
          userMessage:
              'Too many attempts right now. Please wait a few minutes and try again.',
          debugMessage: debugMessage,
          cause: error,
        );
      case 'network-request-failed':
        return AuthFlowException(
          code: AuthFlowErrorCode.networkRequestFailed,
          userMessage:
              'Network error. Please check your internet connection and try again.',
          debugMessage: debugMessage,
          cause: error,
        );
      case 'invalid-credential':
        return AuthFlowException(
          code: AuthFlowErrorCode.wrongPassword,
          userMessage:
              'Invalid login credentials. Please check your email and password.',
          debugMessage: debugMessage,
          cause: error,
        );
      default:
        return AuthFlowException(
          code: AuthFlowErrorCode.unavailable,
          userMessage:
              'Authentication is temporarily unavailable. Please try again.',
          debugMessage: debugMessage ?? error.code,
          cause: error,
        );
    }
  }

  Future<User> _reloadUser(User user, {required String traceId}) async {
    _logAuthEvent(
      'verification_check_start',
      traceId: traceId,
      uid: user.uid,
      blocking: true,
    );
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null || refreshed.uid != user.uid) {
      throw const AuthFlowException(
        code: AuthFlowErrorCode.unavailable,
        userMessage:
            'Authentication is temporarily unavailable. Please try again.',
        debugMessage: 'Current user changed during verification refresh.',
      );
    }
    await refreshed.getIdToken(true);
    _logAuthEvent(
      'verification_check_complete',
      traceId: traceId,
      uid: refreshed.uid,
      emailVerified: refreshed.emailVerified,
      blocking: true,
    );
    return refreshed;
  }

  Future<AuthSignInResult> signIn(String email, String password) async {
    final traceId = _newTraceId('sign_in');
    _logAuthEvent('start', traceId: traceId, blocking: true);
    await AppAnalyticsService.instance.trackAuthFlow('sign_in_start');

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final signedInUser = credential.user;
      if (signedInUser == null) {
        throw const AuthFlowException(
          code: AuthFlowErrorCode.unavailable,
          userMessage:
              'Authentication is temporarily unavailable. Please try again.',
          debugMessage: 'Firebase Auth completed without returning a user.',
        );
      }

      final user = await _reloadUser(signedInUser, traceId: traceId);
      _logAuthEvent(
        'auth_success',
        traceId: traceId,
        uid: user.uid,
        emailVerified: user.emailVerified,
        blocking: true,
      );

      var verificationEmailSent = false;
      if (!user.emailVerified) {
        final verificationResult = await maybeSendVerificationEmail(
          user,
          traceId: traceId,
          reason: 'login_unverified',
        );
        verificationEmailSent = verificationResult.sent;
        await AppAnalyticsService.instance.trackAuthFlow(
          'sign_in',
          status: 'verification_required',
          emailVerified: false,
        );
        _logAuthEvent(
          'verification_required',
          traceId: traceId,
          uid: user.uid,
          emailVerified: false,
          blocking: false,
        );
      } else {
        await AppAnalyticsService.instance.trackAuthFlow(
          'sign_in',
          status: 'ok',
          emailVerified: true,
        );
      }

      try {
        await updateDailyStreak(user.uid);
      } catch (error, stackTrace) {
        _logAuthEvent(
          'daily_streak_failure',
          traceId: traceId,
          uid: user.uid,
          emailVerified: user.emailVerified,
          blocking: false,
          error: error,
        );
        await AppErrorService.instance.recordError(
          error,
          stackTrace,
          category: 'auth',
          source: 'signIn.updateDailyStreak',
        );
      }

      return AuthSignInResult(
        credential: credential,
        user: user,
        emailVerified: user.emailVerified,
        verificationEmailSent: verificationEmailSent,
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      final mapped = _mapAuthException(
        error,
        debugMessage: 'FirebaseAuthException during sign-in.',
      );
      _logAuthEvent(
        'auth_failure',
        traceId: traceId,
        blocking: true,
        error: error.code,
      );
      await AppAnalyticsService.instance.trackAuthFlow(
        'sign_in',
        status: mapped.code.name,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signIn',
      );
      throw mapped;
    } on AuthFlowException catch (error, stackTrace) {
      _logAuthEvent(
        'auth_failure',
        traceId: traceId,
        blocking: true,
        error: error.debugMessage ?? error.userMessage,
      );
      await AppAnalyticsService.instance.trackAuthFlow(
        'sign_in',
        status: error.code.name,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signIn',
      );
      rethrow;
    } catch (error, stackTrace) {
      _logAuthEvent(
        'auth_failure',
        traceId: traceId,
        blocking: true,
        error: error,
      );
      await AppAnalyticsService.instance.trackAuthFlow(
        'sign_in',
        status: AuthFlowErrorCode.unavailable.name,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signIn',
      );
      throw AuthFlowException(
        code: AuthFlowErrorCode.unavailable,
        userMessage:
            'Authentication is temporarily unavailable. Please try again.',
        debugMessage: 'Unexpected sign-in failure.',
        cause: error,
      );
    }
  }

  Future<UserCredential> enterInstantTutorMode() async {
    try {
      debugPrint('Instant Tutor Mode: calling signInAnonymously()');
      final result = await _auth.signInAnonymously();
      final user = result.user;
      if (user != null) {
        debugPrint(
          'Instant Tutor Mode: signInAnonymously() succeeded for uid=${user.uid}, isAnonymous=${user.isAnonymous}',
        );
        _syncInstantTutorModeProfileInBackground(user);
      } else {
        debugPrint(
          'Instant Tutor Mode: signInAnonymously() returned without a user.',
        );
      }
      await AppAnalyticsService.instance.trackAuthFlow(
        'instant_tutor_enter',
        status: 'ok',
      );
      return result;
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'Instant Tutor Mode sign-in failed [${error.code}]: ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('Instant Tutor Mode startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  void _syncInstantTutorModeProfileInBackground(User user) {
    ensureInstantTutorModeProfile(user).catchError((error, stackTrace) {
      debugPrint('Instant Tutor profile sync failed: $error');
      if (stackTrace is StackTrace) {
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  // KEEP ALL YOUR EXISTING METHODS BELOW - DON'T CHANGE THEM
  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String studentNumber,
    required String university,
    required String levelOfStudy,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user != null) {
        await user.sendEmailVerification();
        await _communityBackend.initializeAccountProfile(
          fullName: fullName,
          studentNumber: studentNumber,
          university: university,
          levelOfStudy: levelOfStudy,
        );
        await AppAnalyticsService.instance.trackAuthFlow(
          'sign_up',
          status: 'ok',
        );
      }
      return result;
    } on FirebaseAuthException catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAuthFlow(
        'sign_up',
        status: error.code,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signUp',
      );
      rethrow;
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signUp',
      );
      throw Exception('Something went wrong. Please try again.');
    }
  }

  Future<bool> refreshVerificationStatus(User user, {String? traceId}) async {
    final resolvedTraceId = traceId ?? _newTraceId('verification_refresh');
    final refreshedUser = await _reloadUser(user, traceId: resolvedTraceId);
    return refreshedUser.emailVerified;
  }

  Future<void> ensureVerifiedStudentAccessProfile(
    User user, {
    String? traceId,
    bool force = false,
  }) async {
    if (user.isAnonymous) return;
    final resolvedTraceId = traceId ?? _newTraceId('profile_sync');
    _logAuthEvent(
      'sync_access_profile_start',
      traceId: resolvedTraceId,
      uid: user.uid,
      emailVerified: user.emailVerified,
      blocking: false,
    );
    try {
      await _communityBackend.syncAccessProfile(
        reason: 'authenticated_session',
        traceId: resolvedTraceId,
        force: force,
      );
      _logAuthEvent(
        'sync_access_profile_success',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: user.emailVerified,
        blocking: false,
      );
    } catch (error, stackTrace) {
      _logAuthEvent(
        'sync_access_profile_failure',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: user.emailVerified,
        blocking: false,
        error: error,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'ensureVerifiedStudentAccessProfile',
      );
    }
  }

  Future<void> ensureInstantTutorModeProfile(
    User user, {
    String? traceId,
    bool force = false,
  }) async {
    final resolvedTraceId = traceId ?? _newTraceId('instant_profile_sync');
    _logAuthEvent(
      'sync_access_profile_start',
      traceId: resolvedTraceId,
      uid: user.uid,
      emailVerified: user.emailVerified,
      blocking: false,
    );
    try {
      await _communityBackend.syncAccessProfile(
        reason: 'instant_tutor_session',
        traceId: resolvedTraceId,
        force: force,
      );
      _logAuthEvent(
        'sync_access_profile_success',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: user.emailVerified,
        blocking: false,
      );
    } catch (error, stackTrace) {
      _logAuthEvent(
        'sync_access_profile_failure',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: user.emailVerified,
        blocking: false,
        error: error,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'ensureInstantTutorModeProfile',
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      await AppAnalyticsService.instance.trackVerification(
        action: 'password_reset',
        status: 'sent',
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackVerification(
        action: 'password_reset',
        status: error.code,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'sendPasswordResetEmail',
      );
      rethrow;
    }
  }

  Future<void> resendVerificationEmail(User user) async {
    await maybeSendVerificationEmail(user, reason: 'manual_resend');
  }

  Future<VerificationEmailDispatchResult> maybeSendVerificationEmail(
    User user, {
    String? traceId,
    String reason = 'manual_resend',
  }) async {
    if (user.emailVerified) {
      return const VerificationEmailDispatchResult(
        status: VerificationEmailDispatchStatus.alreadyVerified,
        userMessage: 'Your email is already verified.',
      );
    }

    final resolvedTraceId = traceId ?? _newTraceId('verification_email');
    final now = DateTime.now();
    final lastSentAt = _lastVerificationEmailAtByUser[user.uid];
    if (lastSentAt != null &&
        now.difference(lastSentAt) < const Duration(seconds: 60)) {
      _logAuthEvent(
        'verification_email_cooldown',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: false,
        blocking: false,
      );
      await AppAnalyticsService.instance.trackVerification(
        action: reason,
        status: 'cooldown',
      );
      return const VerificationEmailDispatchResult(
        status: VerificationEmailDispatchStatus.cooldown,
        userMessage:
            'Please wait a moment before requesting another verification email.',
      );
    }

    try {
      await user.sendEmailVerification();
      _lastVerificationEmailAtByUser[user.uid] = now;
      _logAuthEvent(
        'verification_email_sent',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: false,
        blocking: false,
      );
      await AppAnalyticsService.instance.trackVerification(
        action: reason,
        status: 'sent',
      );
      return const VerificationEmailDispatchResult(
        status: VerificationEmailDispatchStatus.sent,
        userMessage: 'Verification email sent. Check your inbox.',
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      _logAuthEvent(
        'verification_email_failure',
        traceId: resolvedTraceId,
        uid: user.uid,
        emailVerified: false,
        blocking: false,
        error: error.code,
      );
      await AppAnalyticsService.instance.trackVerification(
        action: reason,
        status: error.code,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'maybeSendVerificationEmail',
      );
      throw _mapAuthException(
        error,
        debugMessage: 'Verification email dispatch failed.',
      );
    }
  }

  Future<void> updateDailyStreak(String userId) async {
    final userRef = _db.collection('users').doc(userId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() ?? <String, dynamic>{};
      final Timestamp? lastLoginAt = data['lastLoginAt'] as Timestamp?;
      final int currentStreak = (data['streak'] as int?) ?? 0;
      final int bestStreak = (data['streakBest'] as int?) ?? currentStreak;

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      int nextStreak = currentStreak;
      if (lastLoginAt == null) {
        nextStreak = currentStreak > 0 ? currentStreak : 1;
      } else {
        final DateTime lastLogin = lastLoginAt.toDate();
        final DateTime lastDay = DateTime(
          lastLogin.year,
          lastLogin.month,
          lastLogin.day,
        );
        final int diffDays = today.difference(lastDay).inDays;

        if (diffDays == 0) {
          nextStreak = currentStreak == 0 ? 1 : currentStreak;
        } else if (diffDays == 1) {
          nextStreak = currentStreak + 1;
        } else if (diffDays > 1) {
          nextStreak = 1;
        }
      }

      int nextBest = bestStreak;
      if (nextStreak > bestStreak) {
        nextBest = nextStreak;
      }

      transaction.update(userRef, {
        'streak': nextStreak,
        'streakBest': nextBest,
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? studentNumber, // Added to allow updating ID
    String? major,
    String? year,
    String? levelOfStudy,
  }) async {
    try {
      if (userId != _auth.currentUser?.uid) {
        throw Exception('You can only update your own profile.');
      }
      await _communityBackend.updateProfile(
        fullName: fullName,
        major: major,
        levelOfStudy: levelOfStudy,
      );
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'profile',
        source: 'updateUserProfile',
      );
      rethrow;
    }
  }

  // 🔥 UPDATED MIGRATION HELPER
  // 🔥 UPDATED MIGRATION HELPER - THIS IS CRITICAL
  Future<void> addLowerCaseFieldsToExistingUsers() async {
    try {
      final users = await _db.collection('users').get();
      WriteBatch batch = _db.batch();
      int count = 0;
      int totalUpdated = 0;

      for (final user in users.docs) {
        final data = user.data();
        final fullName = data['fullName'] as String?;
        final studentNumber = data['studentNumber'] as String?;
        final email = data['email'] as String?;
        Map<String, dynamic> updates = {};

        if (fullName != null && !data.containsKey('fullNameLowercase')) {
          updates['fullNameLowercase'] = fullName.toLowerCase();
        }
        if (studentNumber != null &&
            !data.containsKey('studentNumberLowercase')) {
          updates['studentNumberLowercase'] = studentNumber.toLowerCase();
        }
        if (email != null && !data.containsKey('emailLowercase')) {
          updates['emailLowercase'] = email.toLowerCase();
        }

        if (updates.isNotEmpty) {
          batch.update(user.reference, updates);
          count++;
          totalUpdated++;
        }

        // Firestore batch limit is 500 operations
        if (count >= 490) {
          await batch.commit();
          batch = _db.batch();
          count = 0;
          // ignore: avoid_print
          print('✅ Batch committed, updated $totalUpdated users so far...');
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      // ignore: avoid_print
      print('🎉 MIGRATION COMPLETE: $totalUpdated users updated.');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Migration error: $e');
      rethrow; // Important: rethrow so you can see the error
    }
  }
}
