import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/login_page_controller.dart';

/// ===============================
/// Delayed Obscure Password Field
/// ===============================
class DelayedObscureTextField extends StatefulWidget {
  final String hintText;
  final Color fieldColor;
  final TextEditingController controller;

  const DelayedObscureTextField({
    super.key,
    required this.hintText,
    required this.fieldColor,
    required this.controller,
  });

  @override
  State<DelayedObscureTextField> createState() =>
      _DelayedObscureTextFieldState();
}

class _DelayedObscureTextFieldState extends State<DelayedObscureTextField> {
  Timer? _timer;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!mounted) return;

    _timer?.cancel();

    setState(() {
      _obscureText = false;
    });

    _timer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;

      setState(() {
        _obscureText = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onTextChanged);
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
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: TextField(
          controller: widget.controller,
          obscureText: _obscureText,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle:
                const TextStyle(color: Colors.white54, fontSize: 16),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// Login Page
/// ===============================
class LoginPageView extends StatefulWidget {
  const LoginPageView({super.key});

  @override
  State<LoginPageView> createState() => _LoginPageViewState();
}

class _LoginPageViewState extends State<LoginPageView> {
  final TextEditingController _emailController =
      TextEditingController();
  final TextEditingController _passwordController =
      TextEditingController();

  late final LoginPageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = LoginPageController(context);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00C09E);
    const backgroundColor = Color(0xFF0F142B);
    const inputFieldColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            FocusManager.instance.primaryFocus?.unfocus();
            await Future.delayed(const Duration(milliseconds: 50));
            if (!mounted) return;
            Navigator.pop(context);
          },
        ),
      ),
      body: SingleChildScrollView(
        padding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.all_inclusive,
                  color: Colors.white, size: 40),
            ),

            const SizedBox(height: 10),
            const Text('Seshly',
                style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    color: Colors.white)),
            const Text('Powered by AutoXyrium',
                style:
                    TextStyle(fontSize: 12, color: Colors.white70)),

            const SizedBox(height: 20),

            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Welcome back',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 15),

                  const Text('Student Email',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 5),
                  _buildInputField(
                    controller: _emailController,
                    hintText: 'Enter your email',
                    fieldColor: inputFieldColor,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 15),
                  const Text('Password',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 5),
                  DelayedObscureTextField(
                    controller: _passwordController,
                    hintText: 'Enter your password',
                    fieldColor: inputFieldColor,
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        await Future.delayed(
                            const Duration(milliseconds: 80));
                        if (!mounted) return;
                        _pageController.navigateToForgotPassword();
                      },
                      child: const Text('Forgot password?',
                          style: TextStyle(color: primaryColor)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  await Future.delayed(
                      const Duration(milliseconds: 100));
                  if (!mounted) return;

                  _pageController.signIn(
                    _emailController.text.trim(),
                    _passwordController.text.trim(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Sign In',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: backgroundColor)),
              ),
            ),

            const SizedBox(height: 15),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account? ",
                    style: TextStyle(color: Colors.white70)),
                GestureDetector(
                  onTap: () async {
                    FocusManager.instance.primaryFocus?.unfocus();
                    await Future.delayed(
                        const Duration(milliseconds: 80));
                    if (!mounted) return;
                    _pageController.navigateToSignUp();
                  },
                  child: const Text('Sign up',
                      style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle:
                const TextStyle(color: Colors.white54, fontSize: 16),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }
}
