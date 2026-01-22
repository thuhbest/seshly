import 'package:flutter/material.dart';
import '../services/mentorship_service.dart';

class MentorshipProfileSheet extends StatefulWidget {
  final MentorshipService service;
  final Map<String, dynamic> existingProfile;
  final Map<String, dynamic> userData;

  const MentorshipProfileSheet({
    super.key,
    required this.service,
    required this.existingProfile,
    required this.userData,
  });

  @override
  State<MentorshipProfileSheet> createState() => _MentorshipProfileSheetState();
}

class _MentorshipProfileSheetState extends State<MentorshipProfileSheet> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);

  late TextEditingController _facultyController;
  late TextEditingController _degreeController;
  late TextEditingController _majorController;

  late String _role;
  late bool _optIn;
  bool _firstGen = false;
  bool _international = false;
  String _fundingStatus = 'Self-funded';
  String _mentorBadge = 'Certified Mentor';

  late Set<String> _careerInterests;
  late Set<String> _personalityTags;
  late Set<String> _focusAreas;
  late Set<String> _availability;
  late Set<String> _riskSignals;

  final List<String> _careerOptions = const ['Tech', 'Finance', 'Research', 'Health', 'Education', 'Business', 'Creative'];
  final List<String> _personalityOptions = const ['Structured', 'Friendly', 'Direct', 'Patient', 'Action-focused', 'Reflective'];
  final List<String> _focusOptions = const ['Academics', 'Career', 'Wellbeing', 'Campus life', 'Time management'];
  final List<String> _availabilityOptions = const ['Mon PM', 'Tue PM', 'Wed PM', 'Thu PM', 'Fri PM', 'Weekend'];
  final List<String> _riskSignalOptions = const [
    'Stress',
    'Academics',
    'Belonging',
    'Motivation',
    'Time management',
    'Financial pressure',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingProfile;
    final userData = widget.userData;

    _facultyController = TextEditingController(text: (existing['faculty'] ?? userData['faculty'] ?? '').toString());
    _degreeController = TextEditingController(text: (existing['degree'] ?? userData['degree'] ?? '').toString());
    _majorController = TextEditingController(text: (existing['major'] ?? userData['major'] ?? '').toString());

    _role = (existing['role'] ?? 'mentee').toString();
    _optIn = existing['optIn'] == true;
    _firstGen = (existing['background']?['firstGen'] ?? false) == true;
    _international = (existing['background']?['international'] ?? false) == true;
    _fundingStatus = (existing['background']?['fundingStatus'] ?? 'Self-funded').toString();
    _mentorBadge = (existing['mentorBadge'] ?? 'Certified Mentor').toString();

    _careerInterests = Set<String>.from((existing['careerInterests'] as List?)?.map((e) => e.toString()) ?? []);
    _personalityTags = Set<String>.from((existing['personalityTags'] as List?)?.map((e) => e.toString()) ?? []);
    _focusAreas = Set<String>.from((existing['focusAreas'] as List?)?.map((e) => e.toString()) ?? []);
    _availability = Set<String>.from((existing['availability'] as List?)?.map((e) => e.toString()) ?? []);
    _riskSignals = Set<String>.from((existing['riskSignals'] as List?)?.map((e) => e.toString()) ?? []);
  }

  @override
  void dispose() {
    _facultyController.dispose();
    _degreeController.dispose();
    _majorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text("Mentorship setup", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          _sectionTitle("Role"),
          Row(
            children: [
              _choiceChip("Mentee", _role == 'mentee', () => setState(() => _role = 'mentee')),
              const SizedBox(width: 10),
              _choiceChip("Mentor", _role == 'mentor', () => setState(() => _role = 'mentor')),
            ],
          ),
          const SizedBox(height: 16),
          _sectionTitle("Academic context"),
          _field("Faculty", _facultyController),
          _field("Degree", _degreeController),
          _field("Major / Course", _majorController),
          const SizedBox(height: 16),
          _sectionTitle("Background"),
          Row(
            children: [
              _toggleChip("First-gen", _firstGen, (value) => setState(() => _firstGen = value)),
              const SizedBox(width: 10),
              _toggleChip("International", _international, (value) => setState(() => _international = value)),
            ],
          ),
          const SizedBox(height: 12),
          _dropdownRow(
            label: "Funding status",
            value: _fundingStatus,
            options: const ['Self-funded', 'Bursary', 'NSFAS', 'Sponsored'],
            onChanged: (value) => setState(() => _fundingStatus = value),
          ),
          const SizedBox(height: 16),
          _sectionTitle("Career interests"),
          _chipWrap(_careerOptions, _careerInterests),
          const SizedBox(height: 16),
          _sectionTitle("Personality"),
          _chipWrap(_personalityOptions, _personalityTags),
          if (_role == 'mentee') ...[
            const SizedBox(height: 16),
            _sectionTitle("Support signals"),
            _chipWrap(_riskSignalOptions, _riskSignals),
          ],
          const SizedBox(height: 16),
          _sectionTitle("Focus areas"),
          _chipWrap(_focusOptions, _focusAreas),
          const SizedBox(height: 16),
          _sectionTitle("Availability"),
          _chipWrap(_availabilityOptions, _availability),
          if (_role == 'mentor') ...[
            const SizedBox(height: 16),
            _sectionTitle("Mentor badge"),
            _dropdownRow(
              label: "Badge",
              value: _mentorBadge,
              options: const ['Certified Mentor', 'Senior Mentor', 'Top Mentor'],
              onChanged: (value) => setState(() => _mentorBadge = value),
            ),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            value: _optIn,
            onChanged: (value) => setState(() => _optIn = value),
            activeColor: tealAccent,
            title: const Text("Opt into privacy-safe analytics", style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              "Admins see trends only. No message content or names.",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: backgroundColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Save mentorship profile", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final userId = widget.service.currentUserId;
    if (userId == null) return;
    await widget.service.upsertProfile(
      userId: userId,
      data: {
        'userId': userId,
        'role': _role,
        'optIn': _optIn,
        'status': 'active',
        'faculty': _facultyController.text.trim(),
        'degree': _degreeController.text.trim(),
        'major': _majorController.text.trim(),
        'year': widget.userData['levelOfStudy'] ?? widget.userData['year'],
        'university': widget.userData['university'],
        'background': {
          'firstGen': _firstGen,
          'international': _international,
          'fundingStatus': _fundingStatus,
        },
        'careerInterests': _careerInterests.toList(),
        'personalityTags': _personalityTags.toList(),
        'focusAreas': _focusAreas.toList(),
        'availability': _availability.toList(),
        'riskSignals': _riskSignals.toList(),
        'displayName': widget.userData['fullName'] ?? widget.userData['displayName'] ?? '',
        if (_role == 'mentor') 'mentorBadge': _mentorBadge,
      },
    );
    if (mounted) Navigator.pop(context);
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: backgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _dropdownRow({
    required String label,
    required String value,
    required List<String> options,
    required void Function(String value) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: backgroundColor,
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(),
              onChanged: (val) => onChanged(val ?? value),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tealAccent : backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? tealAccent : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(color: selected ? backgroundColor : Colors.white70, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _toggleChip(String label, bool selected, void Function(bool) onToggle) {
    return GestureDetector(
      onTap: () => onToggle(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tealAccent.withValues(alpha: 0.2) : backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? tealAccent : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: selected ? tealAccent : Colors.white70)),
      ),
    );
  }

  Widget _chipWrap(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((label) {
        final isSelected = selected.contains(label);
        return GestureDetector(
          onTap: () => setState(() {
            if (isSelected) {
              selected.remove(label);
            } else {
              selected.add(label);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? tealAccent.withValues(alpha: 0.2) : backgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isSelected ? tealAccent : Colors.white12),
            ),
            child: Text(label, style: TextStyle(color: isSelected ? tealAccent : Colors.white70, fontSize: 11)),
          ),
        );
      }).toList(),
    );
  }
}
