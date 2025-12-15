import 'package:flutter/material.dart';

// Dummy screens for navigation simulation
class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Sign Up Screen', style: TextStyle(color: Colors.black, fontSize: 24))),
      );
}

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Forgot Password Screen', style: TextStyle(color: Colors.black, fontSize: 24))),
      );
}

class HomePageScreen extends StatelessWidget {
  const HomePageScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Welcome to Seshly Home!', style: TextStyle(color: Colors.black, fontSize: 24))),
      );
}

class LoginPageController {
  final BuildContext context;

  LoginPageController(this.context);

  void signIn() {
    // Implement your sign-in logic here (e.g., calling an API)
    print('Attempting to sign in...');
    // For now, navigate to a dummy home page
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomePageScreen()),
    );
  }

  void navigateToSignUp() {
    print('Navigating to Sign Up screen...');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SignUpScreen()),
    );
  }

  void navigateToForgotPassword() {
    print('Navigating to Forgot Password screen...');
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
    );
  }
}