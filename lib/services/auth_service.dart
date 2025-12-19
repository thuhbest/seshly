import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ----------------------------
  // Centralised Auth Error Handler
  // ----------------------------
  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'user-not-found':
        return 'Account doesn’t exist.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'Contact support.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  // ----------------------------
  // Sign Up + Create Profile
  // ----------------------------
  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String studentNumber,
    required String university,
  }) async {
    try {
      // 1. Create user in Firebase Auth
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;

      if (user != null) {
        // 2. Send verification email
        await user.sendEmailVerification();

        // 3. Create Firestore user profile
        await _db.collection('users').doc(user.uid).set({
          'fullName': fullName,
          'studentNumber': studentNumber,
          'university': university,
          'email': email,
          'emailVerified': false, // synced later on login
          'isDisabled': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (_) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // ----------------------------
  // Sign In
  // ----------------------------
  Future<UserCredential?> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (_) {
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // ----------------------------
  // Sign Out
  // ----------------------------
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
