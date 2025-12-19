import 'dart:async'; // Import for Timer
import 'package:flutter/material.dart';
import '../controllers/login_page_controller.dart';

// === Custom Widget for Password Delay Feature ===
class DelayedObscureTextField extends StatefulWidget {
  final String hintText;
  final Color fieldColor;
  
  const DelayedObscureTextField({
    super.key,
    required this.hintText,
    required this.fieldColor,
  });

  @override
  State<DelayedObscureTextField> createState() => _DelayedObscureTextFieldState();
}

class _DelayedObscureTextFieldState extends State<DelayedObscureTextField> {
  final TextEditingController _textController = TextEditingController();
  Timer? _timer;
  bool _obscureText = true; // Start with text obscured

  @override
  void initState() {
    super.initState();
    // Listen for changes so we can start the timer whenever a character is typed
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // 1. Cancel any existing timer
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }

    // 2. Temporarily show the text
    setState(() {
      _obscureText = false;
    });

    // 3. Start a timer to hide the text after 1 second (1000 milliseconds)
    _timer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) { // Check if the widget is still in the tree before calling setState
        setState(() {
          _obscureText = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer when the widget is disposed
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.fieldColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0),
        child: TextField(
          controller: _textController,
          obscureText: _obscureText,
          keyboardType: TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 16),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
          ),
        ),
      ),
    );
  }
}
// =================================================

class LoginPageView extends StatelessWidget {
  const LoginPageView({super.key});

  @override
  Widget build(BuildContext context) {
    // Define the consistent colors used across the app
    const Color primaryColor = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);
    const Color inputFieldColor = Color(0xFF1E243A);

    final controller = LoginPageController(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      // 1. Re-enabled Scaffold's keyboard resizing behavior
      resizeToAvoidBottomInset: true, 
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // 2. Wrap the main content in a SingleChildScrollView
      body: SingleChildScrollView( 
        // This padding is necessary to prevent content from touching the screen edges
        // and provides the required spacing at the top when the keyboard is closed.
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 10.0), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            // --- Logo and App Title/Tagline Block ---
            Container(
              width: 70, 
              height: 70,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Center(
                child: Icon(Icons.all_inclusive, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Seshly',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: Colors.white),
            ),
            const SizedBox(height: 3),
            const Text(
              'Powered by AutoXyrium',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.white70),
            ),
            const SizedBox(height: 5),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                '"AI as your teacher, not your academic slave"',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.white70),
              ),
            ),
            const SizedBox(height: 20),

            // --- WELCOME BACK Section ---
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome back',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Sign in to continue your learning journey',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 15),

                  // 3. Student Email Input (Remains the standard field)
                  const Text('Student Email', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 5),
                  _buildInputField(
                    hintText: 'Enter your email',
                    fieldColor: inputFieldColor,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 15),

                  // 4. Password Input (NOW USING THE CUSTOM WIDGET)
                  const Text('Password', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 5),
                  // Using the new custom stateful widget for the 1-second delay
                  DelayedObscureTextField(
                    hintText: 'Enter your password',
                    fieldColor: inputFieldColor,
                  ),

                  // 5. Forgot Password Link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: controller.navigateToForgotPassword,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap), 
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(color: primaryColor, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20), // Adjusted spacing
                ],
              ),
            ),

            // 6. Sign In Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: controller.signIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 5,
                ),
                child: const Text(
                  'Sign In',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: backgroundColor),
                ),
              ),
            ),
            const SizedBox(height: 15),

            // 7. Don't have an account? Sign up
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                GestureDetector(
                  onTap: controller.navigateToSignUp,
                  child: const Text(
                    'Sign up',
                    style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Helper function for the standard Email field (NO change here)
  Widget _buildInputField({
    required String hintText,
    required Color fieldColor,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0),
        child: TextField(
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 16),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
          ),
        ),
      ),
    );
  }
}
