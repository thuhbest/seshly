import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'note_editor_view.dart';

class ArchiveFolderView extends StatefulWidget {
  final String folderId;
  const ArchiveFolderView({super.key, required this.folderId});

  @override
  State<ArchiveFolderView> createState() => _ArchiveFolderViewState();
}

class _ArchiveFolderViewState extends State<ArchiveFolderView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);
  bool _isCreating = false;

  Future<void> _incrementNoteCount(int delta) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final folderRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders')
        .doc(widget.folderId);
    await folderRef.update({'noteCount': FieldValue.increment(delta), 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> _createBlankNote(double baseWidth) async {
    if (_isCreating) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isCreating = true);
    try {
      final noteRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('note_folders')
          .doc(widget.folderId)
          .collection('notes')
          .doc();
      await noteRef.set({
        'title': 'New note',
        'type': 'canvas',
        'canvasHeight': 1400.0,
        'canvasWidth': baseWidth,
        'strokes': [],
        'texts': [],
        'images': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _incrementNoteCount(1);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteEditorView(folderId: widget.folderId, noteId: noteRef.id),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _createPdfNote(double baseWidth) async {
    if (_isCreating) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null) return;

    setState(() => _isCreating = true);
    try {
      final file = result.files.single;
      final fileName = file.name;
      final noteRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('note_folders')
          .doc(widget.folderId)
          .collection('notes')
          .doc();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('notes')
          .child(user.uid)
          .child('${noteRef.id}_${DateTime.now().millisecondsSinceEpoch}.pdf');

      if (kIsWeb) {
        await storageRef.putData(file.bytes!, SettableMetadata(contentType: 'application/pdf'));
      } else if (file.path != null) {
        await storageRef.putFile(File(file.path!));
      } else if (file.bytes != null) {
        await storageRef.putData(file.bytes!, SettableMetadata(contentType: 'application/pdf'));
      }

      final url = await storageRef.getDownloadURL();
      await noteRef.set({
        'title': fileName.replaceAll('.pdf', ''),
        'type': 'pdf',
        'pdfUrl': url,
        'pdfName': fileName,
        'canvasWidth': baseWidth,
        'pageSpacing': 16.0,
        'strokes': [],
        'texts': [],
        'images': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _incrementNoteCount(1);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NoteEditorView(folderId: widget.folderId, noteId: noteRef.id),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showCreateNoteSheet(double baseWidth) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Create note', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            _ActionCard(
              icon: Icons.auto_stories_outlined,
              title: 'Blank notebook',
              subtitle: 'Freeform canvas with pens, text, and images.',
              onTap: () {
                Navigator.pop(context);
                _createBlankNote(baseWidth);
              },
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Import PDF',
              subtitle: 'Write directly on top of a PDF.',
              onTap: () {
                Navigator.pop(context);
                _createPdfNote(baseWidth);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameFolder(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Rename folder', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: backgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders')
        .doc(widget.folderId)
        .update({'title': controller.text.trim(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> _deleteFolder() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Delete folder?', style: TextStyle(color: Colors.white)),
        content: const Text('This will remove the folder and its notes.', style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;

    final folderRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders')
        .doc(widget.folderId);
    final notes = await folderRef.collection('notes').get();
    final batch = FirebaseFirestore.instance.batch();
    for (final note in notes.docs) {
      batch.delete(note.reference);
    }
    batch.delete(folderRef);
    await batch.commit();

    if (mounted) Navigator.pop(context);
  }

  Future<void> _renameNote(DocumentSnapshot doc, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Rename note', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Note title',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: backgroundColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    await doc.reference.update({'title': controller.text.trim(), 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> _deleteNote(DocumentSnapshot doc) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Delete note?', style: TextStyle(color: Colors.white)),
        content: const Text('This note will be removed.', style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    await doc.reference.delete();
    await _incrementNoteCount(-1);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F142B),
        body: Center(child: Text('Sign in to view notes', style: TextStyle(color: Colors.white54))),
      );
    }

    final folderDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders')
        .doc(widget.folderId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: folderDocStream,
      builder: (context, folderSnap) {
        final folderData = folderSnap.data?.data() as Map<String, dynamic>? ?? {};
        final folderName = (folderData['title'] ?? 'Folder').toString();
        final notesStream = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('note_folders')
            .doc(widget.folderId)
            .collection('notes')
            .orderBy('updatedAt', descending: true)
            .snapshots();

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(folderName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                onPressed: () => _renameFolder(folderName),
                icon: const Icon(Icons.edit_outlined, color: Colors.white70),
              ),
              IconButton(
                onPressed: _deleteFolder,
                icon: const Icon(Icons.delete_outline, color: Colors.white54),
              ),
            ],
          ),
          floatingActionButton: _isCreating
              ? const FloatingActionButton(
                  backgroundColor: Color(0xFF00C09E),
                  onPressed: null,
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F142B))),
                )
              : Builder(
                  builder: (context) => FloatingActionButton(
                    backgroundColor: tealAccent,
                    onPressed: () => _showCreateNoteSheet(MediaQuery.of(context).size.width - 40),
                    child: const Icon(Icons.add, color: Color(0xFF0F142B)),
                  ),
                ),
          body: StreamBuilder<QuerySnapshot>(
            stream: notesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
              }
              final notes = snapshot.data!.docs;
              if (notes.isEmpty) {
                return Center(
                  child: Text('No notes yet. Tap + to create one.', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final doc = notes[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = (data['title'] ?? 'Note').toString();
                  final type = (data['type'] ?? 'canvas').toString();
                  final updatedAt = data['updatedAt'] as Timestamp?;
                  final updatedLabel = updatedAt == null
                      ? 'Just now'
                      : DateFormat('dd MMM, HH:mm').format(updatedAt.toDate());

                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NoteEditorView(folderId: widget.folderId, noteId: doc.id),
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: tealAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              type == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.menu_book_rounded,
                              color: tealAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  type == 'pdf' ? 'PDF annotation' : 'Notebook',
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                                const SizedBox(height: 6),
                                Text('Updated $updatedLabel', style: const TextStyle(color: Colors.white30, fontSize: 11)),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            color: backgroundColor,
                            icon: const Icon(Icons.more_vert, color: Colors.white38),
                            onSelected: (value) {
                              if (value == 'rename') {
                                _renameNote(doc, title);
                              } else if (value == 'delete') {
                                _deleteNote(doc);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'rename', child: Text('Rename')),
                              const PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tealAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tealAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
