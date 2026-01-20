import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; 
import '../controllers/login_page_controller.dart';
import '../view/forgot_password_screen.dart';

/// ===============================
/// Reveal Password Field
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
  static const Duration _tapRevealDuration = Duration(seconds: 1);
  static const Duration _holdThreshold = Duration(milliseconds: 500);

  Timer? _revealTimer;
  DateTime? _pressStart;
  bool _obscureText = true;

  void _setObscure(bool value) {
    if (_obscureText == value) return;
    setState(() => _obscureText = value);
  }

  void _handleEyeDown(TapDownDetails details) {
    _pressStart = DateTime.now();
    _revealTimer?.cancel();
    _setObscure(false);
  }

  void _handleEyeUp(TapUpDetails details) {
    final start = _pressStart;
    _pressStart = null;
    if (start == null) {
      _setObscure(true);
      return;
    }

    final heldFor = DateTime.now().difference(start);
    if (heldFor >= _holdThreshold) {
      _setObscure(true);
      return;
    }

    _revealTimer?.cancel();
    _revealTimer = Timer(_tapRevealDuration, () {
      if (!mounted) return;
      _setObscure(true);
    });
  }

  void _handleEyeCancel() {
    _pressStart = null;
    _revealTimer?.cancel();
    _setObscure(true);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.fieldColor,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: TextField(
        controller: widget.controller,
        obscureText: _obscureText,
        enableSuggestions: false,
        autocorrect: false,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: Colors.white54),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          suffixIcon: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _handleEyeDown,
            onTapUp: _handleEyeUp,
            onTapCancel: _handleEyeCancel,
            child: Icon(
              _obscureText ? Icons.visibility_off : Icons.visibility,
              color: Colors.white54,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// Terms of Service & Privacy Policy Screen
/// ===============================
class TermsAndPrivacyScreen extends StatelessWidget {
  const TermsAndPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00C09E);
    const backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Terms & Privacy',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'TERMS OF SERVICE & PRIVACY POLICY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'PART A — TERMS OF SERVICE',
              style: TextStyle(
                color: primaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _buildSectionTitle('1. Eligibility and Age Requirements'),
            _buildParagraph(
                'Seshly is intended for students in secondary school and above.'),
            _buildParagraph(
                'You must be at least 13 years old to create an account.'),
            _buildParagraph(
                'If you are under 16 years old, you may only use Seshly with verifiable parental or legal guardian consent.'),
            _buildParagraph(
                'By using Seshly, you represent and warrant that you meet these eligibility requirements.'),
            
            _buildSectionTitle('2. Account Registration and Security'),
            _buildParagraph(
                'You must create an account to access certain features of the Service.'),
            _buildParagraph(
                'Accounts may be created using a student email address, student number, or other approved identifiers.'),
            _buildParagraph(
                'You are responsible for maintaining the confidentiality of your login credentials.'),
            _buildParagraph(
                'You are fully responsible for all activities that occur under your account.'),
            _buildParagraph(
                'You must notify us immediately of any unauthorized access or security breach.'),
            
            _buildSectionTitle('3. Use of the Service'),
            _buildParagraph(
                'You agree to use Seshly only for lawful and educational purposes.'),
            _buildParagraph('You may not:'),
            _buildBulletPoint('Upload or share harmful, abusive, sexual, or illegal content'),
            _buildBulletPoint('Harass, impersonate, or exploit other users'),
            _buildBulletPoint('Attempt to access accounts, systems, or data without authorization'),
            _buildBulletPoint('Disrupt or interfere with the Service or its infrastructure'),
            _buildParagraph(
                'We reserve the right to investigate and take action against any misuse of the Service.'),
            
            _buildSectionTitle('4. Educational Content, Notes, and User Submissions'),
            _buildParagraph(
                'Users may post academic questions, notes, messages, and other educational content ("User Content").'),
            _buildParagraph('You retain ownership of your User Content.'),
            _buildParagraph(
                'By posting content on Seshly, you grant AutoXyrium a non-exclusive, worldwide, royalty-free license to store, display, reproduce, and use the content solely for operating and improving the Service.'),
            _buildParagraph(
                'You are solely responsible for the accuracy and legality of your content.'),
            
            _buildSectionTitle('5. Tutoring Services and Payments'),
            _buildParagraph('Seshly may connect students with tutors.'),
            _buildParagraph('Tutors are independent users, not employees or agents of AutoXyrium.'),
            _buildParagraph('AutoXyrium does not guarantee academic results, performance, or outcomes.'),
            _buildParagraph('Tutors set their own rates. Payments may be facilitated through third-party payment providers.'),
            _buildParagraph('Unless explicitly stated, payments are non-refundable.'),
            
            _buildSectionTitle('6. Intellectual Property'),
            _buildParagraph(
                'All Seshly software, branding, designs, logos, and proprietary technology are owned by AutoXyrium.'),
            _buildParagraph(
                'You may not copy, modify, distribute, or reverse-engineer any part of the Service without written permission.'),
            _buildParagraph('Unauthorized use of our intellectual property is strictly prohibited.'),
            
            _buildSectionTitle('7. Suspension and Termination'),
            _buildParagraph(
                'We may suspend or terminate your account at any time if you violate this Agreement.'),
            _buildParagraph(
                'We may also suspend access to protect users, comply with law, or maintain platform integrity.'),
            _buildParagraph(
                'You may delete your account at any time, subject to applicable data retention laws.'),
            
            _buildSectionTitle('8. Disclaimers'),
            _buildParagraph('The Service is provided "as is" and "as available."'),
            _buildParagraph('We do not guarantee uninterrupted, error-free, or secure access.'),
            _buildParagraph('AutoXyrium is not responsible for:'),
            _buildBulletPoint('User-generated content'),
            _buildBulletPoint('Tutor conduct or academic outcomes'),
            _buildBulletPoint('Third-party services or links'),
            
            _buildSectionTitle('9. Limitation of Liability'),
            _buildParagraph('To the maximum extent permitted by law:'),
            _buildBulletPoint('AutoXyrium shall not be liable for indirect, incidental, or consequential damages'),
            _buildBulletPoint('Our total liability shall not exceed the amount paid (if any) by you to Seshly'),
            
            _buildSectionTitle('10. Governing Law'),
            _buildParagraph('This Agreement is governed by the laws of the Republic of South Africa, without regard to conflict-of-law principles.'),
            
            _buildSectionTitle('11. Changes to These Terms'),
            _buildParagraph(
                'We may update these Terms from time to time. Continued use of Seshly after changes means you accept the updated Agreement.'),
            
            const SizedBox(height: 30),
            const Text(
              'PART B — PRIVACY POLICY',
              style: TextStyle(
                color: primaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            
            _buildSectionTitle('12. Information We Collect'),
            _buildParagraph('We may collect the following types of information:'),
            _buildSubtitle('a. Personal Information'),
            _buildBulletPoint('Name, email address, student number'),
            _buildBulletPoint('Age or date of birth (for eligibility verification)'),
            _buildSubtitle('b. Usage Data'),
            _buildBulletPoint('App interactions, session data, device information'),
            _buildBulletPoint('Logs, crash reports, and performance metrics'),
            _buildSubtitle('c. Communications'),
            _buildBulletPoint('Messages, support requests, and in-app interactions'),
            
            _buildSectionTitle('13. How We Use Your Information'),
            _buildParagraph('We use your information to:'),
            _buildBulletPoint('Provide and operate the Service'),
            _buildBulletPoint('Authenticate users and secure accounts'),
            _buildBulletPoint('Facilitate tutoring and communication'),
            _buildBulletPoint('Improve features and user experience'),
            _buildBulletPoint('Comply with legal obligations'),
            
            _buildSectionTitle('14. Data Sharing'),
            _buildParagraph('We do not sell personal data.'),
            _buildParagraph('We may share information:'),
            _buildBulletPoint('With service providers (e.g., hosting, payments, analytics)'),
            _buildBulletPoint('To comply with legal requirements'),
            _buildBulletPoint('To protect the rights and safety of users and AutoXyrium'),
            
            _buildSectionTitle('15. Data Security'),
            _buildParagraph(
                'We use reasonable administrative, technical, and organizational safeguards to protect your data. However, no system is completely secure, and we cannot guarantee absolute security.'),
            
            _buildSectionTitle('16. Data Retention'),
            _buildParagraph('We retain personal data only as long as necessary to:'),
            _buildBulletPoint('Provide the Service'),
            _buildBulletPoint('Comply with legal and regulatory requirements'),
            
            _buildSectionTitle('17. Children\'s Privacy'),
            _buildParagraph('Users under 16 require parental or guardian consent.'),
            _buildParagraph('We do not knowingly collect personal data from children without appropriate consent.'),
            _buildParagraph('Parents or guardians may contact us to review or delete a child\'s data.'),
            
            _buildSectionTitle('18. Your Rights'),
            _buildParagraph('Depending on applicable law, you may have the right to:'),
            _buildBulletPoint('Access your personal data'),
            _buildBulletPoint('Correct inaccurate information'),
            _buildBulletPoint('Request deletion of your account'),
            _buildParagraph('Requests can be made through in-app support or official contact channels.'),
            
            _buildSectionTitle('19. Contact Information'),
            _buildParagraph('For questions or concerns regarding these Terms or Privacy Policy:'),
            _buildParagraph('AutoXyrium'),
            _buildParagraph('📧 Email: autoxyrium@gmail.com'),
            
            const SizedBox(height: 30),
            const Center(
              child: Text(
                'Final Acknowledgement',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'By using Seshly, you acknowledge that you have read, understood, and agreed to these Terms of Service and Privacy Policy.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 5),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubtitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 10, bottom: 3),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final LoginPageController _pageController;

  bool _isLoading = false;
  String? _authError;

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
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),

            /// 🔹 OFFICIAL LOGO
            SvgPicture.asset(
              'assets/images/seshly_logo_full.svg',
              height: 120,
              semanticsLabel: 'Seshly Logo',
            ),

            const SizedBox(height: 10),

            /// 🔹 BRANDING
            const Text(
              'Seshly',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            
            /// 🔹 POWERED BY
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.white70),
                children: [
                  TextSpan(text: 'Powered by '),
                  TextSpan(
                    text: 'AutoXyrium',
                    style: TextStyle(color: primaryColor),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            /// 🔹 TAGLINE
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '"AI as your teacher, not your academic slave"',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 25),

            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome back',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Sign in to continue your learning journey',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),

                  const SizedBox(height: 25),

                  const Text(
                    'Student Email',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  _buildInputField(
                    controller: _emailController,
                    hintText: 'Enter your email',
                    fieldColor: inputFieldColor,
                    prefixIcon: Icons.email_outlined,
                  ),

                  const SizedBox(height: 15),

                  const Text(
                    'Password',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  DelayedObscureTextField(
                    controller: _passwordController,
                    hintText: 'Enter your password',
                    fieldColor: inputFieldColor,
                  ),

                  /// 🔹 ERROR MESSAGE
                  if (_authError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _authError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                FocusManager.instance.primaryFocus?.unfocus();
                                await Future.delayed(
                                    const Duration(milliseconds: 80));
                                if (!mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotPasswordScreen(),
                                  ),
                                );
                              },
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(color: primaryColor),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            /// 🔹 SIGN IN BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        setState(() {
                          _isLoading = true;
                          _authError = null;
                        });

                        await _pageController.signIn(
                          _emailController.text.trim(),
                          _passwordController.text.trim(),
                          onSuccess: () {
                            if (!mounted) return;
                            setState(() => _isLoading = false);
                          },
                          onError: (message) {
                            if (!mounted) return;
                            setState(() {
                              _isLoading = false;
                              _authError = message;
                            });
                          },
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const SizedBox(
                          key: ValueKey('loader'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          key: ValueKey('text'),
                          'Sign In',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: backgroundColor,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Don't have an account? ",
                  style: TextStyle(color: Colors.white70),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            await Future.delayed(
                                const Duration(milliseconds: 80));
                            if (!mounted) return;
                            _pageController.navigateToSignUp();
                          },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Sign up',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            // 🔹 TERMS & PRIVACY MESSAGE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'By signing in, you agree to our '),
                    WidgetSpan(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TermsAndPrivacyScreen(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Terms of Service',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: ' and '),
                    WidgetSpan(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TermsAndPrivacyScreen(),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required Color fieldColor,
    IconData? prefixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.white54, size: 20) : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}
