import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'app_analytics_service.dart';
import 'app_error_service.dart';
import 'community_backend_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final CommunityBackendService _communityBackend =
      CommunityBackendService.instance;

  DateTime? _lastVerificationEmailAt;

  // ADD THIS MISSING SIGN IN METHOD
  Future<UserCredential> signIn(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = result.user;
      if (user != null) {
        await _communityBackend.syncAccessProfile();
        await AppAnalyticsService.instance.trackAuthFlow(
          'sign_in',
          status: 'ok',
          emailVerified: user.emailVerified,
        );
        try {
          await updateDailyStreak(user.uid);
        } catch (_) {
          // Ignore streak update failures so sign-in still succeeds.
        }
      }
      return result;
    } on FirebaseAuthException catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAuthFlow(
        'sign_in',
        status: error.code,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signIn',
      );
      rethrow;
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'signIn',
      );
      throw Exception('Something went wrong. Please try again.');
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

  Future<void> ensureVerifiedStudentAccessProfile(User user) async {
    if (user.isAnonymous) return;
    await _communityBackend.syncAccessProfile();
  }

  Future<void> ensureInstantTutorModeProfile(User user) async {
    await _communityBackend.syncAccessProfile();
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
    final now = DateTime.now();
    if (_lastVerificationEmailAt != null &&
        now.difference(_lastVerificationEmailAt!) <
            const Duration(seconds: 60)) {
      throw Exception('Please wait a moment before requesting another email.');
    }

    try {
      await user.sendEmailVerification();
      _lastVerificationEmailAt = now;
      await AppAnalyticsService.instance.trackVerification(
        action: 'email_verification',
        status: 'resent',
      );
    } on FirebaseAuthException catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackVerification(
        action: 'email_verification',
        status: error.code,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'resendVerificationEmail',
      );
      rethrow;
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
