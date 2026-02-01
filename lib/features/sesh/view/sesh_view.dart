import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:seshly/services/sesh_ai_api.dart';
import 'package:seshly/features/sesh/view/sesh_ai_chat_view.dart';
import 'package:seshly/features/sesh/view/sesh_ai_threads_view.dart';
import '../widgets/sesh_tab_bar.dart';
import '../widgets/sesh_feature_card.dart';
import '../widgets/sesh_input_box.dart';
import '../view/vault_view.dart';
import '../view/archive_view.dart';
import 'package:seshly/widgets/responsive.dart';

class SeshView extends StatefulWidget {
  const SeshView({super.key});

  @override
  State<SeshView> createState() => _SeshViewState();
}

class _SeshViewState extends State<SeshView> {
  String _selectedTab = "AI Assist";
  final _api = SeshAiApi();
  bool _busy = false;

  Future<String?> _uploadBytes(Uint8List bytes, String path, String contentType) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final metadata = SettableMetadata(contentType: contentType);
    final task = await ref.putData(bytes, metadata);
    return task.ref.getDownloadURL();
  }

  Future<void> _handleSnapStudy() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to use Snap & Study.')),
        );
      }
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await _uploadBytes(
        bytes,
        'users/${user.uid}/ai/snap/${DateTime.now().millisecondsSinceEpoch}.jpg',
        'image/jpeg',
      );
      if (url == null) throw Exception('Upload failed');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeshAiChatView(
            title: 'Snap & Study',
            subject: 'Snap & Study',
            initialMessage: 'Explain this diagram or image in study-friendly terms.',
            initialAttachments: [url],
            autoSend: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Snap & Study failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSmartNotes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to create Smart Notes.')),
        );
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.bytes == null) return;
    setState(() => _busy = true);
    try {
      final bytes = result.files.single.bytes!;
      final url = await _uploadBytes(
        bytes,
        'users/${user.uid}/ai/notes/input/${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
      );
      if (url == null) throw Exception('Upload failed');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeshAiChatView(
            title: 'Smart Notes',
            subject: 'Smart Notes',
            initialAction: () async {
              final response = await _api.notesEnhance(
                pdfSignedUrl: url,
                subject: 'Smart Notes',
              );
              final pdfUrl = response['smartNotesPdfUrl']?.toString();
              final topics = (response['extractedTopics'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList();
              final message = [
                'Smart notes ready.',
                if (topics.isNotEmpty) 'Topics: ${topics.join(', ')}',
                if (pdfUrl != null) 'Open the PDF from the top right button.',
              ].join('\\n');
              return ChatActionResult(
                messages: [message],
                primaryUrl: pdfUrl,
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Smart Notes failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handlePracticeQuiz() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to generate a practice quiz.')),
        );
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.bytes == null) return;
    setState(() => _busy = true);
    try {
      final bytes = result.files.single.bytes!;
      final url = await _uploadBytes(
        bytes,
        'users/${user.uid}/ai/practice/input/${DateTime.now().millisecondsSinceEpoch}.pdf',
        'application/pdf',
      );
      if (url == null) throw Exception('Upload failed');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SeshAiChatView(
            title: 'Practice Quiz',
            subject: 'Practice Quiz',
            initialAction: () async {
              final response = await _api.practiceGenerate(
                sourceFileSignedUrl: url,
                subject: 'Practice Quiz',
              );
              final questions = (response['questions'] as List<dynamic>? ?? [])
                  .map((q) => q is Map ? q : <String, dynamic>{})
                  .toList();
              final questionText = questions.isEmpty
                  ? 'No questions generated.'
                  : questions
                      .map((q) => '- ${q['question'] ?? ''}')
                      .join('\\n');
              return ChatActionResult(
                messages: ['Here is your practice quiz:\\n$questionText'],
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Practice Quiz failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: pagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Sesh AI", 
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)
                    ),
                    Text(
                      "Your personal study assistant", 
                      style: TextStyle(color: Colors.white54)
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha((0.05 * 255).round()), // fixed withOpacity
                    shape: BoxShape.circle
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF00C09E), size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SeshAiThreadsView()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            SeshTabBar(
              selectedTab: _selectedTab,
              onTabChanged: (tab) => setState(() => _selectedTab = tab),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildActiveView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveView() {
    switch (_selectedTab) {
      case "AI Assist":
        return Column(
          children: [
            SeshFeatureCard(
              title: "Snap & Study",
              description: "Take photos of diagrams and get AI explanations",
              buttonText: "Take Photo",
              icon: Icons.camera_alt_outlined,
              onTap: _busy ? null : _handleSnapStudy,
            ),
            SeshFeatureCard(
              title: "Smart Notes",
              description: "Convert your notes into organized study guides",
              buttonText: "Create Notes",
              icon: Icons.description_outlined,
              onTap: _busy ? null : _handleSmartNotes,
            ),
            SeshFeatureCard(
              title: "Practice Quiz",
              description: "Generate custom quizzes from your study material",
              buttonText: "Start Quiz",
              icon: Icons.track_changes_outlined,
              onTap: _busy ? null : _handlePracticeQuiz,
            ),
            const SizedBox(height: 20),
            const SeshInputBox(),
            const SizedBox(height: 40),
          ],
        );
      case "Vault":
        return const VaultView();
      case "Archive":
        return const ArchiveView();
      default:
        return const Center(
          child: Text(
            "AI Assist Coming Soon", 
            style: TextStyle(color: Colors.white38)
          ),
        );
    }
  }
}
