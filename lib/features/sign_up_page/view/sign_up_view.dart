import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart'; // 🔥 Required for your .svg files
import '../controller/sign_up_controller.dart';
import '../../login/view/login_page_view.dart';

class SignUpView extends StatefulWidget {
  const SignUpView({super.key});

  @override
  State<SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<SignUpView> {
  // Color constants
  static const Color primaryColor = Color(0xFF00C09E);
  static const Color backgroundColor = Color(0xFF0F142B);
  static const Color inputFieldColor = Color(0xFF1E243A);

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _studentNumController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  // University list
  final Map<String, String> _universities = {
    'University of Cape Town': '@myuct.ac.za',
    'University of Pretoria': '@tuks.co.za',
    'Stellenbosch University': '@sun.ac.za',
    'University the Witwatersrand': '@wits.ac.za',
    'University of Johannesburg': '@student.uj.ac.za',
  };

  // 🔥 Level of Study options
  final List<String> _studyLevels = [
    '1st', '2nd', '3rd', '4th', '5th', '6th', 'finally', 
    'Honors', 'Masters', 'PHD', 'High school'
  ];

  String? _selectedUniversity;
  String? _selectedLevel; 

  late SignUpController controller;
  bool _isLoading = false;
  String? _signUpError;

  @override
  void initState() {
    super.initState();
    controller = SignUpController(context);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentNumController.dispose();
    _emailController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (_isLoading) return;

    if (_selectedUniversity == null || _selectedUniversity!.isEmpty) {
      setState(() => _signUpError = 'Please select your university');
      return;
    }

    if (_selectedLevel == null || _selectedLevel!.isEmpty) {
      setState(() => _signUpError = 'Please select your level of study');
      return;
    }

    final email = _emailController.text.trim();
    final emailError = _validateEmail(email);
    if (emailError != null) {
      setState(() => _signUpError = emailError);
      return;
    }

    setState(() {
      _isLoading = true;
      _signUpError = null;
    });

    try {
      await controller.signUp(
        email: email,
        password: _passController.text.trim(),
        fullName: _nameController.text.trim(),
        studentNumber: _studentNumController.text.trim(),
        university: _selectedUniversity!,
        levelOfStudy: _selectedLevel!, 
      );
    } catch (e) {
      setState(() {
        _signUpError = _extractErrorMessage(e.toString());
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Please enter your university email';
    if (!email.contains('@') || !email.contains('.')) return 'Please enter a valid email address';
    if (_selectedUniversity == null) return 'Please select your university first';

    final requiredDomain = _universities[_selectedUniversity!];
    if (requiredDomain == null) return 'Invalid university selection';

    if (!email.toLowerCase().endsWith(requiredDomain)) {
      return 'Email must end with $requiredDomain for ${_selectedUniversity!}';
    }
    return null;
  }

  String _extractErrorMessage(String error) {
    if (error.contains(':')) {
      final parts = error.split(':');
      if (parts.length > 1) return parts.sublist(1).join(':').trim();
    }
    return error;
  }

  String _getEmailHintText() {
    if (_selectedUniversity == null) return 'Select university first';
    return 'e.g. name${_universities[_selectedUniversity!]}';
  }

  @override
  Widget build(BuildContext context) {
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
            // 🔥 OFFICIAL LOGO REPLACEMENT (ONLY CHANGE MADE HERE)
            SvgPicture.asset(
              'assets/images/seshly_logo_full.svg',
              height: 100,
              semanticsLabel: 'Seshly Logo',
            ),
            const SizedBox(height: 10),
            const Text('Seshly', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w500, color: Colors.white)),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 5),
                  const Text('Join the learning journey', style: TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 20),

                  _buildLabel('Full Name'),
                  _buildInputField(controller: _nameController, hintText: 'e.g. Thuh Best', fieldColor: inputFieldColor),
                  const SizedBox(height: 15),

                  _buildLabel('Student Number'),
                  _buildInputField(controller: _studentNumController, hintText: 'e.g. MKNTAB002', fieldColor: inputFieldColor),
                  const SizedBox(height: 15),

                  _buildLabel('University'),
                  _buildDropdown(
                    value: _selectedUniversity,
                    items: _universities.keys.toList(),
                    hint: 'Select your university',
                    onChanged: (val) {
                      setState(() {
                        _selectedUniversity = val;
                        if (_signUpError != null && _signUpError!.contains('Email must end with')) _signUpError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 15),

                  _buildLabel('Level of Study'),
                  _buildDropdown(
                    value: _selectedLevel,
                    items: _studyLevels,
                    hint: 'Select your current level',
                    onChanged: (val) => setState(() => _selectedLevel = val),
                  ),
                  const SizedBox(height: 15),

                  _buildLabel('University Email'),
                  _buildEmailField(
                    controller: _emailController,
                    hintText: _getEmailHintText(),
                    fieldColor: inputFieldColor,
                    selectedUniversity: _selectedUniversity,
                  ),
                  
                  if (_selectedUniversity != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5, left: 5),
                      child: Text(
                        'Must end with ${_universities[_selectedUniversity]!}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                  const SizedBox(height: 15),

                  _buildLabel('Password'),
                  DelayedObscureTextField(
                    controller: _passController,
                    hintText: 'Create a password',
                    fieldColor: inputFieldColor,
                  ),

                  if (_signUpError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_signUpError!, style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
                    ),

                  const SizedBox(height: 30),
                ],
              ),
            ),

            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleSignUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Text('Sign Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: backgroundColor)),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account? ', style: TextStyle(color: Colors.white70)),
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPageView())),
                  child: const Text('Sign In', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5.0),
    child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
  );

  Widget _buildInputField({required TextEditingController controller, required String hintText, required Color fieldColor}) => Container(
    decoration: BoxDecoration(color: fieldColor, borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15.0),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(hintText: hintText, hintStyle: const TextStyle(color: Colors.white54), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 15.0)),
      ),
    ),
  );

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) => Container(
    decoration: BoxDecoration(color: inputFieldColor, borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        dropdownColor: inputFieldColor,
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
        isExpanded: true,
        hint: Text(hint, style: const TextStyle(color: Colors.white54, fontSize: 16)),
        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12.0)),
        items: items.map((String item) => DropdownMenuItem<String>(value: item, child: Text(item, style: const TextStyle(color: Colors.white)))).toList(),
      ),
    ),
  );

  Widget _buildEmailField({required TextEditingController controller, required String hintText, required Color fieldColor, required String? selectedUniversity}) => Container(
    decoration: BoxDecoration(color: fieldColor, borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Colors.white54),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15.0),
          suffixIcon: selectedUniversity != null ? const Icon(Icons.school, color: primaryColor, size: 20) : null,
        ),
        enabled: selectedUniversity != null,
      ),
    ),
  );
}