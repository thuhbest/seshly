import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  final _formKey = GlobalKey<FormState>();
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  late TextEditingController _nameController;
  late TextEditingController _middleNameController;
  late TextEditingController _ageController;
  late TextEditingController _majorController;
  String? _selectedLevel;
  bool _isLoading = true;
  bool _isSaving = false;

  final List<String> _levels = ["1st Year", "2nd Year", "3rd Year", "Honours", "Masters", "PhD"];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      
      String? dbLevel = data['levelOfStudy'];
      if (dbLevel != null && dbLevel.contains("1st")) dbLevel = "1st Year"; 
      if (dbLevel != null && !_levels.contains(dbLevel)) dbLevel = null;

      setState(() {
        _nameController = TextEditingController(text: data['fullName'] ?? "");
        _middleNameController = TextEditingController(text: data['middleName'] ?? "");
        _ageController = TextEditingController(text: data['age']?.toString() ?? "");
        _majorController = TextEditingController(text: data['major'] ?? "");
        _selectedLevel = dbLevel;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: backgroundColor, body: const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E))));

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Edit Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        actions: [
          _SaveButton(onTap: _saveProfile, isLoading: _isSaving),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildInfoNote(),
            const SizedBox(height: 25),
            _buildField("Full Name", _nameController),
            _buildField("Middle Name", _middleNameController),
            _buildField("Age", _ageController, isNumber: true),
            _buildField("Major / Course", _majorController),
            const Text("Level of Study", style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 10),
            _buildDropdown(),
            const SizedBox(height: 30),
            const Divider(color: Colors.white10),
            _buildReadOnlyField("Student Email", FirebaseAuth.instance.currentUser?.email ?? ""),
            _buildReadOnlyField("Student Number", "Verification required to change"),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
      'fullName': _nameController.text.trim(),
      'middleName': _middleNameController.text.trim(),
      'age': int.tryParse(_ageController.text) ?? 0,
      'major': _majorController.text.trim(),
      'levelOfStudy': _selectedLevel,
    });
    if (mounted) Navigator.pop(context);
  }

  Widget _buildField(String label, TextEditingController controller, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedLevel,
          dropdownColor: cardColor,
          isExpanded: true,
          style: const TextStyle(color: Colors.white),
          items: _levels.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
          onChanged: (val) => setState(() => _selectedLevel = val),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      subtitle: Text(value, style: const TextStyle(color: Colors.white54, fontSize: 16)),
      trailing: const Icon(Icons.lock_outline, color: Colors.white10, size: 16),
    );
  }

  Widget _buildInfoNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tealAccent.withValues(alpha: 20), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.info_outline, color: tealAccent, size: 18),
        const SizedBox(width: 10),
        const Expanded(child: Text("Academic ID details are locked for verification.", style: TextStyle(color: Colors.white70, fontSize: 12))),
      ]),
    );
  }
}

class _SaveButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLoading;
  const _SaveButton({required this.onTap, required this.isLoading});
  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.isLoading ? null : widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 15),
            child: widget.isLoading 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C09E)))
              : const Text("Save", style: TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}