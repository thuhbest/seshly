import 'package:flutter/material.dart';
import '../../sign_up_page/view/sign_up_view.dart';
import '../view/forgot_password_screen.dart'; // Added this import
import '../../../services/app_analytics_service.dart';
import '../../../services/app_error_service.dart';
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
      final result = await _authService.signIn(email, password);

      // Allow Flutter Web to clean DOM
      await Future.delayed(const Duration(milliseconds: 120));

      if (!context.mounted) {
        debugPrint(
          'LoginPageController: sign-in completed after widget disposal; skipping UI callbacks.',
        );
        return;
      }
      final navigator = Navigator.of(context);

      if (result.requiresVerification) {
        await AppAnalyticsService.instance.trackAuthFlow(
          'login_controller',
          status: 'verification_required',
          emailVerified: false,
        );
      } else {
        await AppAnalyticsService.instance.trackAuthFlow(
          'login_controller',
          status: 'ok',
          emailVerified: true,
        );
      }

      onSuccess();

      navigator.popUntil((route) => route.isFirst);
    } on AuthFlowException catch (error, stackTrace) {
      debugPrint(
        'LoginPageController auth flow error: ${error.code} ${error.debugMessage ?? ''}',
      );
      await AppAnalyticsService.instance.trackAuthFlow(
        'login_controller',
        status: error.code.name,
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'auth',
        source: 'LoginPageController.signIn',
      );
      onError(error.userMessage);
    } catch (e, stackTrace) {
      debugPrint('LoginPageController generic error: $e');
      await AppErrorService.instance.recordError(
        e,
        stackTrace,
        category: 'auth',
        source: 'LoginPageController.signIn',
      );
      final errorMessage = AppErrorService.instance.userMessageFor(
        e,
        fallback: 'Something went wrong. Please try again.',
      );
      onError(errorMessage);
    }
  }

  /// ===============================
  /// NAVIGATION: SIGN UP
  /// ===============================
  Future<void> navigateToSignUp() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SignUpView()));
  }

  /// ===============================
  /// NAVIGATION: FORGOT PASSWORD
  /// ===============================
  Future<void> navigateToForgotPassword() async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;

    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()));
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
        child: Text('Welcome to Seshly Home!', style: TextStyle(fontSize: 24)),
      ),
    );
  }
}
