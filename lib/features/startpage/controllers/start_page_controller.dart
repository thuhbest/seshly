import 'package:flutter/material.dart';
// Import the new Login View
import '../../login/view/login_page_view.dart';

class StartPageController {
  final BuildContext context;

  StartPageController(this.context);

  /// Handles the navigation when the "Get Started" button is pressed.
  void navigateToNextScreen() {
    // Navigate to the new LoginPageView
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const LoginPageView(),
      ),
    );
    print('Navigating to Login Screen...');
  }
}