import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ===============================
/// Forgot Password Screen
/// ===============================
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// ===============================
  /// Firebase Password Reset
  /// ===============================
  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );
      
      setState(() {
        _emailSent = true;
        _successMessage = 'Password reset email sent! Check your inbox.';
        _isLoading = false;
      });
      
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email address.';
          break;
        case 'invalid-email':
          errorMessage = 'Please enter a valid email address.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many attempts. Please try again later.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your connection.';
          break;
        default:
          errorMessage = 'Failed to send reset email. Please try again.';
      }
      
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
        _isLoading = false;
      });
    }
  }

  /// ===============================
  /// Build Input Field (Matches Login Page)
  /// ===============================
  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required Color fieldColor,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: fieldColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0),
        child: TextFormField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white54),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          validator: validator,
          onFieldSubmitted: (_) => _resetPassword(),
        ),
      ),
    );
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
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            /// 🔹 ICON (Matches Login Screen)
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.lock_reset,
                color: Colors.white,
                size: 40,
              ),
            ),

            const SizedBox(height: 10),

            /// 🔹 TITLE
            const Text(
              'Reset Password',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 5),
            
            const Text(
              'We\'ll send you a link to reset your password',
              textAlign: TextAlign.center, // FIXED: Moved textAlign here
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),

            const SizedBox(height: 30),

            /// 🔹 EMAIL INPUT FORM
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Student Email',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 5),
                  
                  _buildInputField(
                    controller: _emailController,
                    hintText: 'Enter your university email',
                    fieldColor: inputFieldColor,
                    enabled: !_emailSent && !_isLoading,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email address';
                      }
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),

                  /// 🔹 ERROR MESSAGE
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  /// 🔹 SUCCESS MESSAGE
                  if (_successMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A3A2F),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: primaryColor.withAlpha(76), // Replaced withOpacity(0.3) with withAlpha
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: primaryColor, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _successMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  /// 🔹 INSTRUCTIONS (when email sent)
                  if (_emailSent)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📧 Check Your Email',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '1. Open the email from Seshly\n'
                            '2. Click the "Reset Password" link\n'
                            '3. Create a new password\n'
                            '4. Return here to sign in',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            'Didn\'t receive the email?',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Text(
                                'Check your spam folder or ',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: TextButton(
                                  onPressed: _isLoading ? null : _resetPassword,
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'resend',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 30),
                ],
              ),
            ),

            /// 🔹 SEND RESET EMAIL BUTTON
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_emailSent || _isLoading) ? null : _resetPassword,
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
                      : Text(
                          key: ValueKey('text'),
                          _emailSent ? 'Email Sent ✓' : 'Send Reset Link',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: backgroundColor,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// 🔹 BACK TO LOGIN
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Remember your password? ',
                  style: TextStyle(color: Colors.white70),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            /// 🔹 HELP SECTION
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  inputFieldColor.withAlpha(128), // Replaced withOpacity(0.5) with withAlpha
                  Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Need Help?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Use your university email address (.ac.za)\n'
                    '• The reset link expires in 1 hour\n'
                    '• Contact support if you don\'t receive the email',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.email, color: primaryColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Support: autoxyrium@gmail.com',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}