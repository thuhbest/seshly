import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:seshly/services/app_analytics_service.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/sesh_ai_api.dart';

class SeshAIPanel extends StatefulWidget {
  const SeshAIPanel({super.key, this.sessionId});

  final String? sessionId;

  @override
  State<SeshAIPanel> createState() => _SeshAIPanelState();
}

class _SeshAIPanelState extends State<SeshAIPanel> {
  final _api = SeshAiApi();
  bool _busy = false;
  late final String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<String?> _uploadBytes(Uint8List bytes, String path, String contentType) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final metadata = SettableMetadata(contentType: contentType);
    final task = await ref.putData(bytes, metadata);
    return task.ref.getDownloadURL();
  }

  Future<void> _indexSnapshot({
    required String userId,
    required String sessionId,
    required String url,
    required String storagePath,
  }) async {
    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('aiSessions')
        .doc(sessionId)
        .collection('boardSnapshots');
    await collection.add({
      'url': url,
      'storagePath': storagePath,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _handleSummarise() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final urls = <String>[];
      for (final file in result.files) {
        if (file.bytes == null) continue;
        final storagePath = 'users/${user.uid}/ai/sessions/$_sessionId/boards/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        final url = await _uploadBytes(
          file.bytes!,
          storagePath,
          'image/jpeg',
        );
        if (url != null) {
          urls.add(url);
          await _indexSnapshot(
            userId: user.uid,
            sessionId: _sessionId,
            url: url,
            storagePath: storagePath,
          );
        }
      }
      if (urls.isEmpty) throw Exception('No images uploaded');
      final response = await _api.sessionSummarize(
        sessionId: _sessionId,
        boardSnapshotSignedUrls: urls,
        chatLog: const [],
        subject: 'Session Summary',
        participants: [
          {'userId': user.uid, 'role': 'student'},
        ],
      );
      final pdfs = response['pdfUrlsByStudent'] as Map<String, dynamic>?;
      final firstPdf = (pdfs != null && pdfs.values.isNotEmpty)
          ? pdfs.values.first.toString()
          : null;
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E243A),
          title: const Text('Session Summary', style: TextStyle(color: Colors.white)),
          content: Text(
            firstPdf == null ? 'Summary created.' : 'Summary ready in your session files.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'session_summary',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'session_summary',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'session_summary',
      );
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        AppErrorService.instance.userMessageFor(
          error,
          fallback: 'Summary generation failed. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color tealAccent = const Color(0xFF00C09E);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Live Sesh AI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _aiToggle("Capture Board", true, tealAccent),
          const Divider(color: Colors.white10, height: 32),
          const Text("QUICK ACTIONS", style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 12),
          _aiActionButton(Icons.auto_awesome, "Summarise", tealAccent, _busy ? null : _handleSummarise),
          _aiActionButton(Icons.search, "Spot Misconceptions", tealAccent, _busy ? null : _handleSummarise),
        ],
      ),
    );
  }

  Widget _aiToggle(String label, bool value, Color teal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Switch(value: value, onChanged: (v) {}, activeThumbColor: teal),
      ],
    );
  }

  Widget _aiActionButton(IconData icon, String label, Color teal, VoidCallback? onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white10),
          minimumSize: const Size(double.infinity, 45),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: teal),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
