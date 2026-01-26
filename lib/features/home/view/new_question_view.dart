import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:seshly/widgets/responsive.dart';
import 'package:seshly/utils/image_picker_util.dart';


class NewQuestionView extends StatefulWidget {
  const NewQuestionView({super.key});

  @override
  State<NewQuestionView> createState() => _NewQuestionViewState();
}

class _NewQuestionViewState extends State<NewQuestionView> {
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _customSubjectController = TextEditingController();

  String? selectedSubject;
  Uint8List? _imageBytes;
  String? _linkAttachment; // 🔥 Stores the URL link
  bool isCustomSubject = false;
  bool isPosting = false;

  final List<String> subjects = [
    "Mathematics",
    "Physics",
    "Chemistry",
    "Biology",
    "Computer Science",
    "Engineering"
  ];

  @override
  void initState() {
    super.initState();
    _questionController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _questionController.dispose();
    _customSubjectController.dispose();
    super.dispose();
  }

  // 🔥 Professional Link Dialog
  void _showLinkDialog() {
    final TextEditingController linkController = TextEditingController(text: _linkAttachment);
    const Color tealAccent = Color(0xFF00C09E);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E243A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Add Link", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Paste a helpful URL or resource link below.", style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: linkController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "https://example.com",
                hintStyle: const TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: tealAccent.withValues(alpha: 0.3))),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: tealAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _linkAttachment = linkController.text.trim().isEmpty ? null : linkController.text.trim();
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: tealAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Add", style: TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera && !supportsCameraPicker()) {
        _showError("Camera is only supported on mobile. Please select from gallery.");
        return;
      }

      final result = await pickImageBytes(source: source, imageQuality: 70);
      if (result == null) return;
      setState(() => _imageBytes = result.bytes);
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _submitPost() async {
    if (_questionController.text.trim().isEmpty || selectedSubject == null) {
      _showError("Please fill in the question and select a subject.");
      return;
    }

    if (isCustomSubject && _customSubjectController.text.trim().isEmpty) {
      _showError("Please specify the subject name.");
      return;
    }

    setState(() => isPosting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final realName = userDoc.data()?['fullName'] ?? "Seshly User";
      final finalSubject = isCustomSubject ? _customSubjectController.text.trim() : selectedSubject!;

      String? imageUrl;

      if (_imageBytes != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('post_attachments')
            .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

        final TaskSnapshot snap = await storageRef
            .putData(_imageBytes!, SettableMetadata(contentType: 'image/jpeg'))
            .timeout(const Duration(seconds: 20));
        imageUrl = await snap.ref.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection('posts').add({
        'subject': finalSubject,
        'question': _questionController.text.trim(),
        'author': realName,
        'authorId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': 0,
        'comments': 0,
        'isUrgent': false,
        'attachmentUrl': imageUrl,
        'link': _linkAttachment, // 🔥 Now saving the link to Firestore
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint("Error: $e");
      _showError("Failed to post. Check connection or CORS.");
    } finally {
      if (mounted) setState(() => isPosting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    return Scaffold(
      backgroundColor: const Color(0xFF0F142B),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
        title: const Text("New Question", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: isPosting
                ? const SizedBox(width: 60, child: Center(child: CircularProgressIndicator(color: tealAccent, strokeWidth: 2)))
                : ElevatedButton(
                    onPressed: _submitPost,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tealAccent,
                      foregroundColor: const Color(0xFF0F142B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Post", style: TextStyle(fontWeight: FontWeight.bold)),
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
            Container(
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _questionController,
                    minLines: 1,
                    maxLines: 15,
                    maxLength: 5000,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: "What's your question?",
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(20),
                      counterText: "",
                    ),
                  ),
                  
                  if (_imageBytes != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.memory(_imageBytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 8, top: 8,
                            child: GestureDetector(
                              onTap: () => setState(() { _imageBytes = null; }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 🔥 Link Indicator UI
                  if (_linkAttachment != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Row(
                        children: [
                          const Icon(Icons.link, color: tealAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _linkAttachment!,
                              style: const TextStyle(color: tealAccent, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _linkAttachment = null),
                            child: const Icon(Icons.cancel, color: Colors.white24, size: 16),
                          ),
                        ],
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 15, 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("${_questionController.text.length}/5000", style: const TextStyle(color: Colors.white24, fontSize: 12)),
                        Row(
                          children: [
                            _buildAnimatedAttachmentBtn(Icons.image_outlined, () => _pickImage(ImageSource.gallery)),
                            const SizedBox(width: 12),
                            _buildAnimatedAttachmentBtn(Icons.camera_alt_outlined, () => _pickImage(ImageSource.camera)),
                            const SizedBox(width: 12),
                            _buildAnimatedAttachmentBtn(Icons.link, _showLinkDialog), // 🔥 Now calls the dialog
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            const Text("Select Subject", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                ...subjects.map((sub) => _subjectChip(sub)),
                _subjectChip("Other", isOther: true),
              ],
            ),
            if (isCustomSubject) ...[
              const SizedBox(height: 15),
              TextField(
                controller: _customSubjectController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Type subject name...",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: cardColor.withValues(alpha: 0.3),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
            const SizedBox(height: 40),
            _buildAIBox(tealAccent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedAttachmentBtn(IconData icon, VoidCallback onTap) {
    return _ScaleWrapper(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: const Color(0xFF00C09E), size: 20),
      ),
    );
  }

  Widget _buildAIBox(Color tealAccent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tealAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tealAccent.withValues(alpha: 0.2)),
      ),
      child: const Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF00C09E), size: 20),
              SizedBox(width: 10),
              Text("Need help formulating your question?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Text("Sesh AI can help you articulate your question better for more accurate answers.", style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _subjectChip(String label, {bool isOther = false}) {
    bool isSelected = selectedSubject == label;
    return GestureDetector(
      onTap: () => setState(() { selectedSubject = label; isCustomSubject = isOther; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C09E) : const Color(0xFF1E243A).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFF00C09E) : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? const Color(0xFF0F142B) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _ScaleWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _ScaleWrapper({required this.child, required this.onTap});
  @override
  State<_ScaleWrapper> createState() => _ScaleWrapperState();
}

class _ScaleWrapperState extends State<_ScaleWrapper> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _isPressed ? 0.92 : 1.0, duration: const Duration(milliseconds: 100), child: widget.child),
    );
  }
}
