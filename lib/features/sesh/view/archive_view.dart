import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'archive_folder_view.dart';

class ArchiveView extends StatefulWidget {
  const ArchiveView({super.key});

  @override
  State<ArchiveView> createState() => _ArchiveViewState();
}

class _ArchiveViewState extends State<ArchiveView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);
  bool _didSeedDefaults = false;

  static const List<int> _folderColors = [
    0xFF4EA1FF,
    0xFF9B7BFF,
    0xFF00C09E,
    0xFFFFA24A,
    0xFFF8719D,
    0xFF65D6A8,
  ];

  static const Map<String, IconData> _folderIcons = {
    'architecture': Icons.architecture,
    'science': Icons.science_outlined,
    'laptop': Icons.laptop_mac,
    'book': Icons.menu_book_outlined,
    'palette': Icons.palette,
    'article': Icons.description_outlined,
  };

  @override
  void initState() {
    super.initState();
    _ensureDefaultFolders();
  }

  Future<void> _ensureDefaultFolders() async {
    if (_didSeedDefaults) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _didSeedDefaults = true;

    final foldersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders');
    final existing = await foldersRef.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    final defaults = [
      {'title': 'Mathematics', 'icon': 'architecture', 'color': _folderColors[0]},
      {'title': 'Physics', 'icon': 'science', 'color': _folderColors[1]},
      {'title': 'Computer Science', 'icon': 'laptop', 'color': _folderColors[2]},
    ];
    for (final folder in defaults) {
      final doc = foldersRef.doc();
      batch.set(doc, {
        'title': folder['title'],
        'icon': folder['icon'],
        'color': folder['color'],
        'noteCount': 0,
        'isDefault': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  IconData _iconFromName(String? name) {
    if (name == null) return Icons.folder;
    return _folderIcons[name] ?? Icons.folder;
  }

  Color _colorFromValue(dynamic value) {
    if (value is int) return Color(value);
    return tealAccent;
  }

  Future<void> _showFolderEditor({DocumentSnapshot? doc}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final bool isEditing = doc != null;
    final data = doc?.data() as Map<String, dynamic>? ?? {};
    final TextEditingController controller =
        TextEditingController(text: data['title']?.toString() ?? '');
    String selectedIcon = data['icon']?.toString() ?? _folderIcons.keys.first;
    int selectedColor = (data['color'] is int) ? data['color'] as int : _folderColors[2];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit folder' : 'New folder',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Folder name',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Icon', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _folderIcons.entries.map((entry) {
                      final bool selected = selectedIcon == entry.key;
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedIcon = entry.key),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selected ? tealAccent : backgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: selected ? tealAccent : Colors.white12),
                          ),
                          child: Icon(entry.value, color: selected ? const Color(0xFF0F142B) : Colors.white70),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Accent color', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: _folderColors.map((colorValue) {
                      final bool selected = selectedColor == colorValue;
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedColor = colorValue),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(colorValue),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = controller.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Add a folder name.')),
                          );
                          return;
                        }
                        final folderRef = FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .collection('note_folders');
                        if (isEditing) {
                          await doc!.reference.update({
                            'title': name,
                            'icon': selectedIcon,
                            'color': selectedColor,
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        } else {
                          await folderRef.add({
                            'title': name,
                            'icon': selectedIcon,
                            'color': selectedColor,
                            'noteCount': 0,
                            'isDefault': false,
                            'createdAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        }
                        if (mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: const Color(0xFF0F142B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(isEditing ? 'Save changes' : 'Create folder'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteFolder(DocumentSnapshot doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('Delete folder?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove the folder and its notes.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final notesRef = doc.reference.collection('notes');
    final notes = await notesRef.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final note in notes.docs) {
      batch.delete(note.reference);
    }
    batch.delete(doc.reference);
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sign in to view your archive', style: TextStyle(color: Colors.white54)));
    }

    final foldersStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders')
        .orderBy('createdAt', descending: false)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: foldersStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
        }
        final docs = snapshot.data!.docs;
        final int totalNotes = docs.fold<int>(
          0,
          (total, doc) => total + ((doc.data() as Map<String, dynamic>)['noteCount'] as int? ?? 0),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Study Archive',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ArchiveClickWrapper(
                  onTap: () => _showFolderEditor(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: tealAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_rounded, color: Color(0xFF00C09E), size: 16),
                        SizedBox(width: 6),
                        Text('New folder', style: TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '$totalNotes notes',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 18),
            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: const Text(
                  'No folders yet. Create your first archive folder.',
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              ...docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = (data['title'] ?? 'Folder').toString();
                final noteCount = (data['noteCount'] as int?) ?? 0;
                final icon = _iconFromName(data['icon']?.toString());
                final accent = _colorFromValue(data['color']);

                return ArchiveClickWrapper(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArchiveFolderView(folderId: doc.id),
                    ),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: accent, size: 24),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('$noteCount notes', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          color: backgroundColor,
                          icon: const Icon(Icons.more_vert, color: Colors.white38),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showFolderEditor(doc: doc);
                            } else if (value == 'delete') {
                              _deleteFolder(doc);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
          ],
        );
      },
    );
  }
}

class ArchiveClickWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const ArchiveClickWrapper({super.key, required this.child, required this.onTap});

  @override
  State<ArchiveClickWrapper> createState() => _ArchiveClickWrapperState();
}

class _ArchiveClickWrapperState extends State<ArchiveClickWrapper> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}
