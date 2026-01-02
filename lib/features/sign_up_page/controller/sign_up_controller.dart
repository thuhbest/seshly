import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../services/auth_service.dart';

class SignUpController {
  final BuildContext context;
  final AuthService _authService = AuthService();

  SignUpController(this.context);

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String studentNumber,
    required String university,
    required String levelOfStudy, // 🔥 ADDED: New required parameter
  }) async {
    // 🛑 Validate all fields first - Including levelOfStudy
    if (email.isEmpty || password.isEmpty || fullName.isEmpty || 
        studentNumber.isEmpty || university.isEmpty || levelOfStudy.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    // 🔧 Validate email format
    if (!email.contains('@') || !email.contains('.')) {
      _showError('Please enter a valid university email address');
      return;
    }

    // 🔧 Validate university email format
    if (!email.toLowerCase().contains('.ac.')) {
      _showError('Please use your university email address (.ac.za domain)');
      return;
    }

    // 🔧 Validate password strength
    if (password.length < 6) {
      _showError('Password must be at least 6 characters long');
      return;
    }

    try {
      await _authService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        studentNumber: studentNumber,
        university: university,
        levelOfStudy: levelOfStudy, // 🔥 ADDED: Pass to AuthService
      );
      
      // ✅ Success - show confirmation and navigate
      if (context.mounted) {
        _showSuccess('Account created successfully! Please check your email to verify your account.');
        
        await Future.delayed(const Duration(seconds: 2));
        
        if (context.mounted) {
          Navigator.of(context).pop(); // Back to Login
        }
      }
    } on FirebaseAuthException catch (e) {
      final errorMessage = _mapFirebaseErrorToHumanMessage(e);
      _showError(errorMessage);
    } catch (e) {
      print('⚠️ SignUpController generic error: $e');
      _showError(_handleGenericError(e));
    }
  }

  /// ===============================
  /// FIREBASE ERROR TO HUMAN MESSAGE
  /// ===============================
  String _mapFirebaseErrorToHumanMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead or use a different email.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters with a mix of letters and numbers.';
      case 'invalid-email':
        return 'Please enter a valid university email address (e.g., name@university.ac.za).';
      case 'operation-not-allowed':
        return 'Email/password sign-up is not enabled. Please contact support.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many sign-up attempts. Please wait a few minutes and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'missing-android-pkg-name':
      case 'missing-ios-bundle-id':
        return 'App configuration error. Please contact support.';
      default:
        // Try to make the Firebase message more user-friendly
        if (e.message != null && e.message!.contains('network')) {
          return 'Network error. Please check your internet connection and try again.';
        }
        return 'Registration failed: ${e.message ?? "Please check your information and try again."}';
    }
  }

  /// ===============================
  /// GENERIC ERROR HANDLER
  /// ===============================
  String _handleGenericError(dynamic e) {
    final errorString = e.toString().toLowerCase();
    
    if (errorString.contains('network') || 
        errorString.contains('socket') || 
        errorString.contains('timeout') ||
        errorString.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    
    if (errorString.contains('firebase') || errorString.contains('auth')) {
      return 'Authentication service error. Please try again.';
    }
    
    if (errorString.contains('firestore') || errorString.contains('database')) {
      return 'Database error. Please try again.';
    }
    
    return 'Something went wrong during registration. Please try again.';
  }

  /// ===============================
  /// UI HELPERS
  /// ===============================
  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF00C09E), // Your primary color
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }
}