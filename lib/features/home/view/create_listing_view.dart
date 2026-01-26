import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:seshly/widgets/responsive.dart';
import 'package:seshly/utils/image_picker_util.dart';

class CreateListingView extends StatefulWidget {
  const CreateListingView({super.key});

  @override
  State<CreateListingView> createState() => _CreateListingViewState();
}

class _CreateListingViewState extends State<CreateListingView> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  String _selectedCategory = "Notes";
  bool _isDigital = true;
  bool _isSubmitting = false;
  Uint8List? _imageBytes;

  final List<String> _categories = const ["Notes", "Tech", "Bags", "Stationery", "Other"];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await pickImageBytes(source: ImageSource.gallery, imageQuality: 80);
      if (result == null) return;

      setState(() {
        _imageBytes = result.bytes;
      });
    } catch (_) {
      _showSnack("Could not pick image.");
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_imageBytes == null) return null;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('marketplace_items')
        .child('${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

    final uploadTask = storageRef.putData(
      _imageBytes!,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final snap = await uploadTask.timeout(const Duration(seconds: 30));
    return await snap.ref.getDownloadURL();
  }

  int _parsePrice(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  Future<void> _submitListing() async {
    if (_isSubmitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("Please sign in to create a listing.");
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final price = _parsePrice(_priceController.text);

    if (title.isEmpty) {
      _showSnack("Add a title for your listing.");
      return;
    }
    if (price <= 0) {
      _showSnack("Enter a valid price.");
      return;
    }
    if (_selectedCategory == "Notes" && _isDigital) {
      _showSnack("Digital notes must be listed from your Notes editor so Seshly can store and deliver them.");
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final sellerName = (userData['fullName'] ?? userData['displayName'] ?? "Student").toString();
      final imageUrl = await _uploadImage(user.uid);

      await FirebaseFirestore.instance.collection('marketplace_items').add({
        'title': title,
        'description': description,
        'price': price,
        'currency': 'ZAR',
        'category': _selectedCategory,
        'isDigital': _isDigital,
        'sellerId': user.uid,
        'sellerName': sellerName,
        'imageUrl': imageUrl,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack("Listing created.");
        Navigator.pop(context);
      }
    } catch (_) {
      _showSnack("Failed to create listing.");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Create Listing", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: _isSubmitting
                ? const SizedBox(
                    width: 70,
                    child: Center(child: CircularProgressIndicator(color: tealAccent, strokeWidth: 2)),
                  )
                : ElevatedButton(
                    onPressed: _submitListing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tealAccent,
                      foregroundColor: const Color(0xFF0F142B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("List", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: _imageBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, color: Colors.white.withValues(alpha: 0.4), size: 36),
                          const SizedBox(height: 10),
                          const Text("Add cover image", style: TextStyle(color: Colors.white54)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            _buildLabel("Title"),
            _buildInputField(
              controller: _titleController,
              hint: "e.g. Calculus 1 Notes",
            ),
            const SizedBox(height: 16),
            _buildLabel("Description"),
            _buildInputField(
              controller: _descriptionController,
              hint: "What is included?",
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            _buildLabel("Price (ZAR)"),
            _buildInputField(
              controller: _priceController,
              hint: "e.g. 45",
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _buildLabel("Category"),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categories.map((category) {
                final bool selected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? tealAccent : cardColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? tealAccent : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        color: selected ? const Color(0xFF0F142B) : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  const Text("Digital item", style: TextStyle(color: Colors.white)),
                  const Spacer(),
                  Switch(
                    value: _isDigital,
                    onChanged: (val) => setState(() => _isDigital = val),
                    activeThumbColor: tealAccent,
                    activeTrackColor: tealAccent.withValues(alpha: 25),
                  ),
                ],
              ),
            ),
            if (_selectedCategory == "Notes" && _isDigital) ...[
              const SizedBox(height: 10),
              Text(
                "Digital notes are listed from your Notes editor so Seshly can store and deliver them. "
                "Physical notes are fine here.",
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    const Color cardColor = Color(0xFF1E243A);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: cardColor.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
