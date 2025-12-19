import 'package:flutter/material.dart';
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
  }) async {
    try {
      await _authService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        studentNumber: studentNumber,
        university: university,
      );
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration Successful!')),
        );
        Navigator.of(context).pop(); // Back to Login
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}