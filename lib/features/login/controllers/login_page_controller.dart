import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // IMPORTANT
import '../../sign_up_page/view/sign_up_view.dart';
import '../view/forgot_password_screen.dart'; // Added this import
import '../../../services/auth_service.dart';

class LoginPageController {
  final BuildContext context;
  final AuthService _authService = AuthService();

  LoginPageController(this.context);

  /// ===============================
  /// SIGN IN (WITH PROPER ERROR HANDLING)
  /// ===============================
  Future<void> signIn(
    String email,
    String password, {
    required VoidCallback onSuccess,
    required Function(String message) onError,
  }) async {
    // Guard: empty fields
    if (email.isEmpty || password.isEmpty) {
      onError('Please fill in all fields');
      return;
    }

    try {
      // Firebase sign-in - THIS NOW WORKS BECAUSE WE ADDED signIn METHOD
      await _authService.signIn(email, password);

      // Allow Flutter Web to clean DOM
      await Future.delayed(const Duration(milliseconds: 120));

      if (!context.mounted) {
        onError('Operation interrupted. Please try again.');
        return;
      }

      // Call success callback
      onSuccess();

      // Navigation after successful login
      Navigator.of(context).popUntil((route) => route.isFirst);

    } on FirebaseAuthException catch (e) {
      // NOW WE CAN CATCH FirebaseAuthException DIRECTLY!
      // Use debugPrint instead of print for production
      debugPrint('LoginPageController caught FirebaseAuthException: ${e.code}');
      final errorMessage = _mapFirebaseErrorToHumanMessage(e);
      onError(errorMessage);
    } catch (e) {
      // Generic errors
      debugPrint('LoginPageController generic error: $e');
      final errorMessage = _handleGenericError(e);
      onError(errorMessage);
    }
  }

  /// ===============================
  /// FIREBASE ERROR TO HUMAN MESSAGE
  /// ===============================
  String _mapFirebaseErrorToHumanMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'user-not-found':
        return 'No account found with this email. Please check or sign up.';
      case 'invalid-email':
        return 'Please enter a valid email address (e.g., name@university.ac.za).';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many login attempts. Please wait a few minutes and try again.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled. Contact support.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection and try again.';
      case 'invalid-credential':
        return 'Invalid login credentials. Please check your email and password.';
      case 'requires-recent-login':
        return 'Session expired. Please sign in again.';
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      default:
        // Try to make the Firebase message more user-friendly
        if (e.message != null && e.message!.contains('network')) {
          return 'Network error. Please check your internet connection and try again.';
        }
        return 'Login failed: ${e.message ?? "Please check your credentials and try again."}';
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
    
    return 'Something went wrong. Please try again.';
  }

  /// ===============================
  /// NAVIGATION: SIGN UP
  /// ===============================
  Future<void> navigateToSignUp() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpView()),
    );
  }

  /// ===============================
  /// NAVIGATION: FORGOT PASSWORD
  /// ===============================
  Future<void> navigateToForgotPassword() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  /// ===============================
  /// UI HELPERS (OPTIONAL - KEEP OR REMOVE)
  /// ===============================
  // Only remove this if you're not using it anywhere
  // If you ARE using it, keep it. Otherwise, comment it out:
  /*
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
  */
}

/// ===============================
/// TEMP HOME SCREEN (KEEP FOR NOW)
/// ===============================
class HomePageScreen extends StatelessWidget {
  const HomePageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Welcome to Seshly Home!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}