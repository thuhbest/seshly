import 'package:flutter/material.dart';
import '../../sign_up_page/view/sign_up_view.dart';
import '../../../services/auth_service.dart';

class LoginPageController {
  final BuildContext context;
  final AuthService _authService = AuthService();

  LoginPageController(this.context);

  /// ===============================
  /// SIGN IN
  /// ===============================
  Future<void> signIn(String email, String password) async {
    // 🛑 Guard: empty fields
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please fill in all fields');
      return;
    }

    try {
      // 🔑 Firebase sign-in
      await _authService.signIn(email, password);

      // 🧠 IMPORTANT: allow Flutter Web to clean DOM
      await Future.delayed(const Duration(milliseconds: 120));

      if (!context.mounted) return;

      // ✅ Navigate to Home (replace stack)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const HomePageScreen(),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      _showSnackBar(_friendlyError(e));
    }
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
  /// UI HELPERS
  /// ===============================
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

  String _friendlyError(dynamic error) {
    final message = error.toString().toLowerCase();

    if (message.contains('user-not-found')) {
      return 'No account found with this email';
    }
    if (message.contains('wrong-password')) {
      return 'Incorrect password';
    }
    if (message.contains('invalid-email')) {
      return 'Invalid email address';
    }
    if (message.contains('network')) {
      return 'Network error. Please try again';
    }

    return 'Login failed. Please try again';
  }
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

/// ===============================
/// TEMP FORGOT PASSWORD SCREEN
/// ===============================
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Forgot Password Screen',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
