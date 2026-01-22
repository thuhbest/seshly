import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TutorApplicationView extends StatefulWidget {
  const TutorApplicationView({super.key});

  @override
  State<TutorApplicationView> createState() => _TutorApplicationViewState();
}

class _TutorApplicationViewState extends State<TutorApplicationView> {
  final TextEditingController _mainSubject1 = TextEditingController();
  final TextEditingController _mainSubject2 = TextEditingController();
  final TextEditingController _minorSubject1 = TextEditingController();
  final TextEditingController _minorSubject2 = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  final TextEditingController _highestLevelController = TextEditingController();
  final TextEditingController _qualificationController = TextEditingController();
  final TextEditingController _institutionController = TextEditingController();
  final TextEditingController _fieldController = TextEditingController();
  final TextEditingController _gradYearController = TextEditingController();
  final TextEditingController _yearsExpController = TextEditingController();
  final TextEditingController _studentsTaughtController = TextEditingController();
  final TextEditingController _experienceSummaryController = TextEditingController();
  final TextEditingController _languagesController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _availabilityWindowController = TextEditingController();
  final TextEditingController _orgNameController = TextEditingController();
  final TextEditingController _orgRoleController = TextEditingController();
  final TextEditingController _orgWebsiteController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _proofLinkController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  bool _isSubmitting = false;
  bool _isLoading = true;
  bool _acceptFee = false;
  bool _acceptConduct = false;
  bool _confirmAccuracy = false;
  bool _consentVerification = false;

  String _targetAudience = "Varsity Students";
  String _tutorType = "Individual";
  String _teachingMode = "Online";
  String? _status;
  final List<String> _availabilityDays = [];

  final List<String> _audiences = const ["Varsity Students", "High School", "Both"];
  final List<String> _tutorTypes = const ["Individual", "Organization", "Family", "Agency"];
  final List<String> _teachingModes = const ["Online", "In-person", "Both"];
  final List<String> _days = const ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  @override
  void initState() {
    super.initState();
    _loadExisting();
    _rateController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _mainSubject1.dispose();
    _mainSubject2.dispose();
    _minorSubject1.dispose();
    _minorSubject2.dispose();
    _rateController.dispose();
    _highestLevelController.dispose();
    _qualificationController.dispose();
    _institutionController.dispose();
    _fieldController.dispose();
    _gradYearController.dispose();
    _yearsExpController.dispose();
    _studentsTaughtController.dispose();
    _experienceSummaryController.dispose();
    _languagesController.dispose();
    _locationController.dispose();
    _availabilityWindowController.dispose();
    _orgNameController.dispose();
    _orgRoleController.dispose();
    _orgWebsiteController.dispose();
    _idNumberController.dispose();
    _proofLinkController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final appDoc = await FirebaseFirestore.instance
          .collection('tutor_applications')
          .doc(user.uid)
          .get();

      Map<String, dynamic>? data;
      if (appDoc.exists) {
        data = appDoc.data();
      } else {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        data = (userDoc.data()?['tutorProfile'] as Map<String, dynamic>?) ?? {};
      }

      if (data != null && data.isNotEmpty) {
        final mainSubjects = List<String>.from(data['mainSubjects'] ?? []);
        final minorSubjects = List<String>.from(data['minorSubjects'] ?? []);
        if (mainSubjects.isNotEmpty) _mainSubject1.text = mainSubjects[0];
        if (mainSubjects.length > 1) _mainSubject2.text = mainSubjects[1];
        if (minorSubjects.isNotEmpty) _minorSubject1.text = minorSubjects[0];
        if (minorSubjects.length > 1) _minorSubject2.text = minorSubjects[1];

        _rateController.text = (data['baseRate'] ?? "").toString();
        _highestLevelController.text = (data['highestLevel'] ?? "").toString();
        _qualificationController.text = (data['qualification'] ?? "").toString();
        _institutionController.text = (data['institution'] ?? "").toString();
        _fieldController.text = (data['fieldOfStudy'] ?? "").toString();
        _gradYearController.text = (data['graduationYear'] ?? "").toString();
        _yearsExpController.text = (data['yearsExperience'] ?? "").toString();
        _studentsTaughtController.text = (data['studentsTaught'] ?? "").toString();
        _experienceSummaryController.text = (data['experienceSummary'] ?? "").toString();
        final languagesRaw = data['languages'];
        if (languagesRaw is List) {
          _languagesController.text = languagesRaw.join(', ');
        } else if (languagesRaw is String) {
          _languagesController.text = languagesRaw;
        }
        _locationController.text = (data['location'] ?? "").toString();
        _availabilityWindowController.text = (data['availabilityWindow'] ?? "").toString();
        _orgNameController.text = (data['organizationName'] ?? "").toString();
        _orgRoleController.text = (data['organizationRole'] ?? "").toString();
        _orgWebsiteController.text = (data['organizationWebsite'] ?? "").toString();
        _idNumberController.text = (data['idNumber'] ?? "").toString();
        _proofLinkController.text = (data['verificationLink'] ?? "").toString();
        _referenceController.text = (data['referenceContact'] ?? "").toString();

        _targetAudience = (data['targetAudience'] ?? _targetAudience).toString();
        _tutorType = (data['tutorType'] ?? _tutorType).toString();
        _teachingMode = (data['teachingMode'] ?? _teachingMode).toString();
        final availabilityRaw = data['availabilityDays'];
        _availabilityDays.clear();
        if (availabilityRaw is List) {
          _availabilityDays.addAll(List<String>.from(availabilityRaw));
        }
        _status = (data['status'] ?? _status).toString();
        if (_status == 'pending') {
          await _promotePendingTutor(user.uid);
          _status = 'active';
        }
      }
    } catch (_) {
      _showSnack("Could not load tutor profile.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _parseRate(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  int _displayRate(int baseRate) {
    return (baseRate * 1.2).ceil();
  }

  List<String> _parseList(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _submitApplication() async {
    if (_isSubmitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("Please sign in to apply.");
      return;
    }

    final mainSubjects = [
      _mainSubject1.text.trim(),
      _mainSubject2.text.trim(),
    ].where((value) => value.isNotEmpty).toList();
    final minorSubjects = [
      _minorSubject1.text.trim(),
      _minorSubject2.text.trim(),
    ].where((value) => value.isNotEmpty).toList();

    if (mainSubjects.isEmpty) {
      _showSnack("Add at least one main subject.");
      return;
    }
    if (mainSubjects.length + minorSubjects.length > 4) {
      _showSnack("Maximum of 4 subjects total.");
      return;
    }

    final baseRate = _parseRate(_rateController.text);
    if (baseRate <= 0) {
      _showSnack("Enter a valid rate per minute.");
      return;
    }

    final highestLevel = _highestLevelController.text.trim();
    if (highestLevel.isEmpty) {
      _showSnack("Add the highest level you can tutor.");
      return;
    }

    final qualification = _qualificationController.text.trim();
    final institution = _institutionController.text.trim();
    final yearsExp = _yearsExpController.text.trim();
    if (qualification.isEmpty || institution.isEmpty || yearsExp.isEmpty) {
      _showSnack("Add your qualification, institution, and experience.");
      return;
    }

    if (_languagesController.text.trim().isEmpty) {
      _showSnack("Add the languages you can tutor in.");
      return;
    }

    if (_availabilityDays.isEmpty || _availabilityWindowController.text.trim().isEmpty) {
      _showSnack("Add your availability days and time window.");
      return;
    }

    if (!_acceptFee || !_acceptConduct || !_confirmAccuracy) {
      _showSnack("Please accept the terms and confirm accuracy.");
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final data = {
        'userId': user.uid,
        'fullName': userData['fullName'] ?? user.displayName ?? "Student",
        'email': user.email ?? "",
        'mainSubjects': mainSubjects,
        'minorSubjects': minorSubjects,
        'baseRate': baseRate,
        'displayRate': _displayRate(baseRate),
        'targetAudience': _targetAudience,
        'highestLevel': highestLevel,
        'tutorType': _tutorType,
        'organizationName': _orgNameController.text.trim(),
        'organizationRole': _orgRoleController.text.trim(),
        'organizationWebsite': _orgWebsiteController.text.trim(),
        'qualification': qualification,
        'institution': institution,
        'fieldOfStudy': _fieldController.text.trim(),
        'graduationYear': _gradYearController.text.trim(),
        'yearsExperience': yearsExp,
        'studentsTaught': _studentsTaughtController.text.trim(),
        'experienceSummary': _experienceSummaryController.text.trim(),
        'languages': _parseList(_languagesController.text),
        'location': _locationController.text.trim(),
        'availabilityDays': _availabilityDays,
        'availabilityWindow': _availabilityWindowController.text.trim(),
        'teachingMode': _teachingMode,
        'idNumber': _idNumberController.text.trim(),
        'verificationLink': _proofLinkController.text.trim(),
        'referenceContact': _referenceController.text.trim(),
        'acceptFee': _acceptFee,
        'acceptConduct': _acceptConduct,
        'confirmAccuracy': _confirmAccuracy,
        'consentVerification': _consentVerification,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'activatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('tutor_applications')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'tutorProfile': {
          'mainSubjects': mainSubjects,
          'minorSubjects': minorSubjects,
          'baseRate': baseRate,
          'displayRate': _displayRate(baseRate),
          'targetAudience': _targetAudience,
          'highestLevel': highestLevel,
          'tutorType': _tutorType,
          'organizationName': _orgNameController.text.trim(),
          'teachingMode': _teachingMode,
          'languages': _parseList(_languagesController.text),
          'location': _locationController.text.trim(),
          'availabilityDays': _availabilityDays,
          'availabilityWindow': _availabilityWindowController.text.trim(),
          'status': 'active',
        },
        'tutorStatus': 'active',
        'tutorSubjects': [...mainSubjects, ...minorSubjects],
        'tutorActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() => _status = 'active');
        _showSnack("You're now a tutor. Go online to appear in search.");
      }
    } catch (_) {
      _showSnack("Could not submit application.");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _promotePendingTutor(String userId) async {
    await FirebaseFirestore.instance
        .collection('tutor_applications')
        .doc(userId)
        .set({
      'status': 'active',
      'activatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'tutorStatus': 'active',
      'tutorActiveAt': FieldValue.serverTimestamp(),
      'tutorProfile': {
        'status': 'active',
      },
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    final int baseRate = _parseRate(_rateController.text);
    final int displayRate = baseRate > 0 ? _displayRate(baseRate) : 0;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Apply as a Tutor", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: tealAccent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_status != null) ...[
                    _infoBanner("Application status: ${_status!.toUpperCase()}"),
                    const SizedBox(height: 14),
                  ],
                  _infoBanner(
                    "Seshly adds a 20% platform fee on top of your base rate. Example: R5/min becomes R6/min.",
                  ),
                  const SizedBox(height: 10),
                  _infoBanner(
                    "You become a tutor immediately after submitting. Your profile appears to students only while you're online.",
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("Tutor type"),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _tutorTypes.map((type) => _buildChip(type, type == _tutorType, () {
                      setState(() => _tutorType = type);
                    })).toList(),
                  ),
                  if (_tutorType != "Individual") ...[
                    const SizedBox(height: 14),
                    _buildSectionTitle("Organization / Family"),
                    _buildInputRow(
                      cardColor,
                      child: Column(
                        children: [
                          _buildInputField(_orgNameController, "Organization or family name"),
                          const SizedBox(height: 10),
                          _buildInputField(_orgRoleController, "Your role or title"),
                          const SizedBox(height: 10),
                          _buildInputField(_orgWebsiteController, "Website or social link"),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildSectionTitle("Subjects (max 4 total)"),
                  _buildInputRow(
                    cardColor,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildInputField(_mainSubject1, "Main subject 1")),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInputField(_mainSubject2, "Main subject 2")),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildInputField(_minorSubject1, "Minor subject 1")),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInputField(_minorSubject2, "Minor subject 2")),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Target audience"),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _audiences.map((audience) => _buildChip(
                      audience,
                      audience == _targetAudience,
                      () => setState(() => _targetAudience = audience),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Highest level you can tutor"),
                  _buildInputRow(
                    cardColor,
                    child: _buildInputField(_highestLevelController, "e.g. 3rd year statistics"),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("Qualifications"),
                  _buildInputRow(
                    cardColor,
                    child: Column(
                      children: [
                        _buildInputField(_qualificationController, "Highest qualification"),
                        const SizedBox(height: 10),
                        _buildInputField(_institutionController, "Institution"),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildInputField(_fieldController, "Field of study")),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInputField(_gradYearController, "Graduation year", keyboardType: TextInputType.number)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("Experience"),
                  _buildInputRow(
                    cardColor,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildInputField(_yearsExpController, "Years tutoring", keyboardType: TextInputType.number)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInputField(_studentsTaughtController, "Learners helped", keyboardType: TextInputType.number)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildInputField(_experienceSummaryController, "Experience summary", maxLines: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("Teaching mode"),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _teachingModes.map((mode) => _buildChip(
                      mode,
                      mode == _teachingMode,
                      () => setState(() => _teachingMode = mode),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Languages"),
                  _buildInputRow(
                    cardColor,
                    child: _buildInputField(_languagesController, "English, isiZulu, Afrikaans"),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Location / timezone"),
                  _buildInputRow(
                    cardColor,
                    child: _buildInputField(_locationController, "e.g. Durban, SAST"),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("Availability"),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _days.map((day) {
                      final bool selected = _availabilityDays.contains(day);
                      return _buildChip(
                        day,
                        selected,
                        () {
                          setState(() {
                            if (selected) {
                              _availabilityDays.remove(day);
                            } else {
                              _availabilityDays.add(day);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  _buildInputRow(
                    cardColor,
                    child: _buildInputField(_availabilityWindowController, "Time window e.g. 16:00 - 20:00"),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("Rate per minute (base)"),
                  _buildInputRow(
                    cardColor,
                    child: _buildInputField(_rateController, "e.g. 5", keyboardType: TextInputType.number),
                  ),
                  if (displayRate > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Students see: R$displayRate / min (20% platform fee included).",
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildSectionTitle("Verification (optional but recommended)"),
                  _buildInputRow(
                    cardColor,
                    child: Column(
                      children: [
                        _buildInputField(_idNumberController, "ID or passport number"),
                        const SizedBox(height: 10),
                        _buildInputField(_proofLinkController, "Proof of qualification link"),
                        const SizedBox(height: 10),
                        _buildInputField(_referenceController, "Reference contact (email or phone)"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("Agreements"),
                  _buildAgreementRow(
                    "I understand Seshly adds a 20% platform fee to my base rate.",
                    _acceptFee,
                    (val) => setState(() => _acceptFee = val),
                  ),
                  _buildAgreementRow(
                    "I agree to uphold tutor conduct, punctuality, and student safety.",
                    _acceptConduct,
                    (val) => setState(() => _acceptConduct = val),
                  ),
                  _buildAgreementRow(
                    "I confirm the information provided is accurate.",
                    _confirmAccuracy,
                    (val) => setState(() => _confirmAccuracy = val),
                  ),
                  _buildAgreementRow(
                    "I consent to verification if required.",
                    _consentVerification,
                    (val) => setState(() => _consentVerification = val),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitApplication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: const Color(0xFF0F142B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(_isSubmitting ? "Submitting..." : "Submit application"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInputRow(Color cardColor, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }

  Widget _buildInputField(TextEditingController controller, String hint,
      {TextInputType? keyboardType, int maxLines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        border: InputBorder.none,
      ),
    );
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00C09E) : const Color(0xFF1E243A).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? const Color(0xFF00C09E) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF0F142B) : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildAgreementRow(String text, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF00C09E),
            activeTrackColor: const Color(0xFF00C09E).withValues(alpha: 50),
          ),
        ],
      ),
    );
  }
}
