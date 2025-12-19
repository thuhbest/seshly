import 'package:flutter/material.dart';
import '../controller/sign_up_controller.dart';
import '../../login/view/login_page_view.dart'; // To reuse DelayedObscureTextField

class SignUpView extends StatefulWidget {
  const SignUpView({super.key});

  @override
  State<SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<SignUpView> {
  // 1. Define the controllers to capture user input
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _studentNumController = TextEditingController();
  final TextEditingController _uniController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  late SignUpController controller;

  // ADDED: loading state
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    controller = SignUpController(context);
  }

  @override
  void dispose() {
    // Clean up controllers when the widget is removed
    _nameController.dispose();
    _studentNumController.dispose();
    _uniController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  // ADDED: async signup handler with proper state handling
  Future<void> _handleSignUp() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      await controller.signUp(
        email: _emailController.text.trim(),
        password: _passController.text.trim(),
        fullName: _nameController.text.trim(),
        studentNumber: _studentNumController.text.trim(),
        university: _uniController.text.trim(),
      );
    } catch (e) {
      rethrow; // let controller handle UI messaging
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);
    const Color inputFieldColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // --- Logo Block ---
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
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),

            // --- Form Section ---
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Join the learning journey',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 20),

                  _buildLabel('Full Name'),
                  _buildInputField(
                    controller: _nameController,
                    hintText: 'e.g. Thuh Best',
                    fieldColor: inputFieldColor,
                  ),
                  const SizedBox(height: 15),

                  _buildLabel('Student Number'),
                  _buildInputField(
                    controller: _studentNumController,
                    hintText: 'e.g. MKNTAB002',
                    fieldColor: inputFieldColor,
                  ),
                  const SizedBox(height: 15),

                  _buildLabel('University'),
                  _buildInputField(
                    controller: _uniController,
                    hintText: 'e.g. University of Cape Town',
                    fieldColor: inputFieldColor,
                  ),
                  const SizedBox(height: 15),

                  _buildLabel('University Email'),
                  _buildInputField(
                    controller: _emailController,
                    hintText: 'name@university.ac.za',
                    fieldColor: inputFieldColor,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 15),

                  _buildLabel('Password'),
                  DelayedObscureTextField(
                    controller: _passController,
                    hintText: 'Create a password',
                    fieldColor: inputFieldColor,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),

            // --- Sign Up Button ---
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                // UPDATED: loading-aware handler
                onPressed: _isLoading ? null : _handleSignUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: backgroundColor,
                        ),
                      )
                    : const Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: backgroundColor,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5.0),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
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
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle:
                const TextStyle(color: Colors.white54, fontSize: 16),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 15.0),
          ),
        ),
      ),
    );
  }
}
