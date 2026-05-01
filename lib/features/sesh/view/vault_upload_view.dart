import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/widgets/responsive.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class VaultUploadView extends StatefulWidget {
  const VaultUploadView({super.key});

  @override
  State<VaultUploadView> createState() => _VaultUploadViewState();
}

class _VaultUploadViewState extends State<VaultUploadView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  
  String _selectedType = "Past Paper";
  Uint8List? _selectedBytes;
  String? _selectedFileName;
  bool _isUploading = false;

  Future<Uint8List?> _readFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    final stream = file.readStream;
    if (stream == null) return null;
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
      withReadStream: true,
    );
    if (result != null) {
      final picked = result.files.single;
      final bytes = await _readFileBytes(picked);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not read the selected file.")));
        return;
      }
      setState(() {
        _selectedFileName = picked.name;
        _selectedBytes = bytes;
      });
    }
  }

  Future<void> _handleUpload() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (!_formKey.currentState!.validate() || _selectedBytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text("Please select a PDF and fill all fields")));
      return;
    }

    setState(() => _isUploading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text("You need to be logged in to upload.")));
        setState(() => _isUploading = false);
      }
      return;
    }

    try {
      final fileName = "vault/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf";
      final ref = FirebaseStorage.instance.ref().child(fileName);
      await ref.putData(_selectedBytes!, SettableMetadata(contentType: 'application/pdf'));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('vault').add({
        'userId': user.uid,
        'subject': _subjectController.text.trim().toUpperCase(),
        'year': _yearController.text.trim(),
        'type': _selectedType,
        'fileUrl': url,
        'stars': 0,
        'starredBy': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    final bool hasFile = _selectedBytes != null;
    final String fileLabel = _selectedFileName ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFF0F142B),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text("Upload Material")),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              PressableScale(
                onTap: _pickFile,
                borderRadius: BorderRadius.circular(20),
                pressedScale: 0.98,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: cardColor, 
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: hasFile ? tealAccent : Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf_rounded, color: hasFile ? tealAccent : Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        hasFile ? "File: $fileLabel" : "Tap to select PDF",
                        style: TextStyle(color: hasFile ? Colors.white : Colors.white24, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 25),
              _buildDropdown(),
              _buildField("Course Code / Subject", _subjectController, "e.g. CSC1015F"),
              _buildField("Year", _yearController, "e.g. 2024", isNumber: true),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isUploading ? null : _handleUpload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: tealAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isUploading 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F142B)))
                  : const Text("Publish to Vault", style: TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, String hint, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white10),
            filled: true, fillColor: const Color(0xFF1E243A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Material Type", style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: const Color(0xFF1E243A), borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedType,
              dropdownColor: const Color(0xFF1E243A),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              items: ["Past Paper", "Notes", "Question Bank"].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _selectedType = val!),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
