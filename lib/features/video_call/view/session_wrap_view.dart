import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:seshly/services/sesh_ai_api.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class SessionWrapView extends StatefulWidget {
  const SessionWrapView({super.key, this.sessionId});

  final String? sessionId;

  @override
  State<SessionWrapView> createState() => _SessionWrapViewState();
}

class _SessionWrapViewState extends State<SessionWrapView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);
  final _api = SeshAiApi();
  late final String _sessionId;

  String _selectedStyle = "Exam Focused";
  bool _includeHomework = true;
  bool _isGenerating = false;
  String? _lastSummaryUrl;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Session Wrap", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Row(
        children: [
          _buildSummaryControls(),
          Container(width: 1, color: Colors.white.withValues(alpha: 25)),
          Expanded(child: _buildDeliverablesGrid()),
        ],
      ),
      bottomNavigationBar: _buildFinalActionFooter(),
    );
  }

  Widget _buildSummaryControls() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader("Session Pack Settings"),
          const SizedBox(height: 20),
          _checkOption("Generate Group Summary", true),
          _checkOption("Individual Corrections", true),
          _checkOption("Key Mistakes Heatmap", true),
          _checkOption("Homework & Next Steps", _includeHomework, 
            onChanged: (v) => setState(() => _includeHomework = v!)),
          const SizedBox(height: 30),
          _sectionHeader("AI Explanation Style"),
          const SizedBox(height: 15),
          _buildStylePill("Short & Exam Focused"),
          const SizedBox(height: 8),
          _buildStylePill("Deep Concept Explanation"),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: tealAccent.withValues(alpha: 25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: tealAccent, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("Sesh AI will compile your board snapshots into session packs.",
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverablesGrid() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader("Individual Student Packs"),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.2,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => _buildStudentPackCard(index),
            ),
          ),
          if (_lastSummaryUrl != null) ...[
            const SizedBox(height: 12),
            Text("Latest pack ready to share.", style: TextStyle(color: tealAccent, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentPackCard(int index) {
    final names = ["Luko", "Thuhbest", "Sarah", "Mike"];
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 13)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(backgroundColor: tealAccent, radius: 12),
            title: Text(names[index], style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            trailing: Icon(Icons.check_circle, color: tealAccent, size: 18),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: backgroundColor.withValues(alpha: 128),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(child: Icon(Icons.article_outlined, color: Colors.white10, size: 32)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("3 Misconceptions identified", style: TextStyle(color: Colors.white38, fontSize: 10)),
                Text("Ready", style: TextStyle(color: tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFinalActionFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 25))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Deliverable: Native Sesh Notes + PDF", style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text("Recipient: 4 Students", style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          SizedBox(
            width: 250,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (_isGenerating) return;
                _generateAndSendPacks();
              },
              child: _isGenerating 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF0F142B), strokeWidth: 2))
                : const Text("Generate & Send All Packs", style: TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndSendPacks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Please sign in to generate packs.');
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final urls = await _loadIndexedSnapshots(user.uid, _sessionId);

      if (urls.isEmpty) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['png', 'jpg', 'jpeg'],
          allowMultiple: true,
          withData: true,
          withReadStream: true,
        );
        if (result == null || result.files.isEmpty) {
          setState(() => _isGenerating = false);
          return;
        }

        for (final file in result.files) {
          final bytes = await _readFileBytes(file);
          if (bytes == null) continue;
          final storagePath = 'users/${user.uid}/ai/sessions/$_sessionId/boards/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          final url = await _uploadBytes(
            bytes,
            storagePath,
            _contentTypeForName(file.name),
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
      }

      if (urls.isEmpty) throw Exception('No snapshots uploaded.');

      final response = await _api.sessionSummarize(
        sessionId: _sessionId,
        boardSnapshotSignedUrls: urls,
        chatLog: const [],
        subject: _selectedStyle,
        participants: [
          {'userId': user.uid, 'role': 'student'},
        ],
      );

      final pdfs = response['pdfUrlsByStudent'] as Map<String, dynamic>?;
      final firstUrl = (pdfs != null && pdfs.values.isNotEmpty) ? pdfs.values.first.toString() : null;
      setState(() => _lastSummaryUrl = firstUrl);

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: cardColor,
          title: const Text('Session Packs Ready', style: TextStyle(color: Colors.white)),
          content: Text(
            firstUrl == null ? 'Session packs were generated.' : 'Session packs were generated and saved.',
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
    } catch (error) {
      _showSnack('Generate failed: $error');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
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

  Future<List<String>> _loadIndexedSnapshots(String userId, String sessionId) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('aiSessions')
        .doc(sessionId)
        .collection('boardSnapshots')
        .orderBy('createdAt', descending: false)
        .get();
    return snap.docs
        .map((doc) => (doc.data()['url'] ?? '').toString())
        .where((url) => url.trim().isNotEmpty)
        .toList();
  }

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

  String _contentTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.1));
  }

  Widget _checkOption(String label, bool val, {Function(bool?)? onChanged}) {
    return CheckboxListTile(
      value: val,
      onChanged: onChanged ?? (v) {},
      title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeColor: tealAccent,
      checkColor: backgroundColor,
      // 🔥 FIXED: Use proper parameter name
      controlAffinity: ListTileControlAffinity.leading, 
    );
  }

  Widget _buildStylePill(String label) {
    bool isSelected = _selectedStyle == label;
    return PressableScale(
      onTap: () => setState(() => _selectedStyle = label),
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: isSelected ? tealAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? tealAccent : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? backgroundColor : Colors.white60, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
}
