import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:seshly/utils/image_picker_util.dart';

enum NoteTool { pen, pencil, highlighter, eraser, text, move }

class NoteStroke {
  final List<Offset> points;
  final int color;
  final double width;
  final double opacity;
  final String tool;

  NoteStroke({
    required this.points,
    required this.color,
    required this.width,
    required this.opacity,
    required this.tool,
  });

  Map<String, dynamic> toMap() {
    return {
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'color': color,
      'width': width,
      'opacity': opacity,
      'tool': tool,
    };
  }

  factory NoteStroke.fromMap(Map<String, dynamic> map) {
    final rawPoints = (map['points'] as List?) ?? [];
    final points = rawPoints.map((point) {
      final data = point as Map<String, dynamic>;
      return Offset(
        (data['x'] as num?)?.toDouble() ?? 0,
        (data['y'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
    return NoteStroke(
      points: points,
      color: (map['color'] as num?)?.toInt() ?? Colors.black.toARGB32(),
      width: (map['width'] as num?)?.toDouble() ?? 2.0,
      opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
      tool: (map['tool'] ?? 'pen').toString(),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<NoteStroke> strokes;
  final double scale;
  final double yOffset;

  _StrokePainter({required this.strokes, required this.scale, required this.yOffset});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = Color(stroke.color).withValues(alpha: stroke.opacity)
        ..strokeWidth = stroke.width * scale
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (int i = 1; i < stroke.points.length; i++) {
        final p1 = stroke.points[i - 1];
        final p2 = stroke.points[i];
        final Offset a = Offset(p1.dx * scale, p1.dy * scale - yOffset);
        final Offset b = Offset(p2.dx * scale, p2.dy * scale - yOffset);
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.scale != scale || oldDelegate.yOffset != yOffset;
  }
}

class _PaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFD9CFC0)
      ..strokeWidth = 1;
    for (double y = 36; y < size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    final marginPaint = Paint()
      ..color = const Color(0xFFE8B4B4)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(48, 0), Offset(48, size.height), marginPaint);
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) => false;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? activeColor;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final Color selectedColor = activeColor ?? tealAccent;
    final Color selectedIconColor = selectedColor == tealAccent ? const Color(0xFF0F142B) : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedColor : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? selectedColor : Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? selectedIconColor : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? selectedIconColor : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E243A).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
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

class NoteTextItem {
  final String id;
  final String text;
  final double x;
  final double y;
  final double fontSize;
  final String fontFamily;
  final int color;

  NoteTextItem({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.fontFamily,
    required this.color,
  });

  NoteTextItem copyWith({
    String? text,
    double? x,
    double? y,
    double? fontSize,
    String? fontFamily,
    int? color,
  }) {
    return NoteTextItem(
      id: id,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      color: color ?? this.color,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'x': x,
      'y': y,
      'fontSize': fontSize,
      'fontFamily': fontFamily,
      'color': color,
    };
  }

  factory NoteTextItem.fromMap(Map<String, dynamic> map) {
    return NoteTextItem(
      id: (map['id'] ?? const Uuid().v4()).toString(),
      text: (map['text'] ?? '').toString(),
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 16,
      fontFamily: (map['fontFamily'] ?? 'Roboto').toString(),
      color: (map['color'] as num?)?.toInt() ?? Colors.black.toARGB32(),
    );
  }
}

class NoteImageItem {
  final String id;
  final String url;
  final double x;
  final double y;
  final double width;
  final double height;

  NoteImageItem({
    required this.id,
    required this.url,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  NoteImageItem copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return NoteImageItem(
      id: id,
      url: url,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  factory NoteImageItem.fromMap(Map<String, dynamic> map) {
    return NoteImageItem(
      id: (map['id'] ?? const Uuid().v4()).toString(),
      url: (map['url'] ?? '').toString(),
      x: (map['x'] as num?)?.toDouble() ?? 0,
      y: (map['y'] as num?)?.toDouble() ?? 0,
      width: (map['width'] as num?)?.toDouble() ?? 160,
      height: (map['height'] as num?)?.toDouble() ?? 120,
    );
  }
}

class NoteEditorView extends StatefulWidget {
  final String folderId;
  final String noteId;
  const NoteEditorView({super.key, required this.folderId, required this.noteId});

  @override
  State<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends State<NoteEditorView> {
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);
  final Color tealAccent = const Color(0xFF00C09E);
  final ScrollController _scrollController = ScrollController();
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey _canvasKey = GlobalKey();
  final List<NoteStroke> _strokes = [];
  final List<NoteTextItem> _texts = [];
  final List<NoteImageItem> _images = [];
  final TextEditingController _inlineTextController = TextEditingController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  final SpeechToText _speech = SpeechToText();
  NoteStroke? _activeStroke;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _allowPop = false;
  bool _isInlineEditing = false;
  bool _isListening = false;
  bool _speechAvailable = false;
  bool _speechInitializing = false;
  bool _isDraggingAsset = false;
  double _canvasHeight = 1400;
  double _canvasWidth = 360;
  double _pageSpacing = 16;
  double _pdfScrollOffset = 0;
  double _textFontSize = 18;
  String _noteTitle = 'Note';
  String _noteType = 'canvas';
  String? _pdfUrl;
  String? _pdfName;
  String? _folderTitle;
  String _textFontFamily = _fontFamilies.first;
  NoteTool _activeTool = NoteTool.pen;
  Color _activeColor = const Color(0xFF1F1F1F);
  double _strokeWidth = 3.0;
  int? _editingTextIndex;
  Offset _inlineTextPosition = const Offset(40, 120);

  static const List<Color> _noteColors = [
    Color(0xFF1F1F1F),
    Color(0xFF2B4EFF),
    Color(0xFFD64545),
    Color(0xFF2E8B57),
    Color(0xFFFF8C00),
    Color(0xFF7B5CFF),
  ];

  static const List<String> _fontFamilies = [
    'Roboto',
    'Georgia',
    'Times New Roman',
    'Courier',
    'Arial',
  ];

  static const int _maxRemoteBytes = 25 * 1024 * 1024;
  final Map<String, Uint8List> _remoteBytesCache = {};

  @override
  void initState() {
    super.initState();
    _inlineTextFocusNode.addListener(_handleInlineFocusChange);
    _loadNote();
  }

  @override
  void dispose() {
    _inlineTextFocusNode.removeListener(_handleInlineFocusChange);
    _inlineTextFocusNode.dispose();
    _inlineTextController.dispose();
    if (_speech.isListening) {
      _speech.stop();
    }
    _scrollController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final folderRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('note_folders')
        .doc(widget.folderId);
    final noteRef = folderRef.collection('notes').doc(widget.noteId);
    final folderSnap = await folderRef.get();
    final noteSnap = await noteRef.get();
    if (!noteSnap.exists) {
      setState(() => _isLoading = false);
      return;
    }
    final folderData = folderSnap.data();
    final data = noteSnap.data() ?? <String, dynamic>{};
    setState(() {
      _folderTitle = folderData?['title']?.toString();
      _noteTitle = (data['title'] ?? 'Note').toString();
      _noteType = (data['type'] ?? 'canvas').toString();
      _canvasHeight = (data['canvasHeight'] as num?)?.toDouble() ?? 1400;
      _canvasWidth = (data['canvasWidth'] as num?)?.toDouble() ?? 360;
      _pageSpacing = (data['pageSpacing'] as num?)?.toDouble() ?? 16;
      _pdfUrl = data['pdfUrl']?.toString();
      _pdfName = data['pdfName']?.toString();
      _strokes
        ..clear()
        ..addAll(((data['strokes'] as List?) ?? []).map((e) => NoteStroke.fromMap(e as Map<String, dynamic>)));
      _texts
        ..clear()
        ..addAll(((data['texts'] as List?) ?? []).map((e) => NoteTextItem.fromMap(e as Map<String, dynamic>)));
      _images
        ..clear()
        ..addAll(((data['images'] as List?) ?? []).map((e) => NoteImageItem.fromMap(e as Map<String, dynamic>)));
      _isLoading = false;
    });
  }

  void _handleInlineFocusChange() {
    if (!_inlineTextFocusNode.hasFocus) {
      _commitInlineText();
    }
  }

  Future<Uint8List?> _loadStorageBytes(String url) async {
    final cached = _remoteBytesCache[url];
    if (cached != null) return cached;
    try {
      final data = await FirebaseStorage.instance.refFromURL(url).getData(_maxRemoteBytes);
      if (data == null) return null;
      _remoteBytesCache[url] = data;
      return data;
    } catch (_) {
      return null;
    }
  }

  String _safeFileName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    if (cleaned.isEmpty) return 'seshly_note';
    return cleaned;
  }

  void _selectTool(NoteTool tool) {
    if (_activeTool == tool) return;
    if (_isInlineEditing) {
      _commitInlineText();
    }
    setState(() => _activeTool = tool);
  }

  bool get _isDrawingTool {
    return _activeTool == NoteTool.pen ||
        _activeTool == NoteTool.pencil ||
        _activeTool == NoteTool.highlighter ||
        _activeTool == NoteTool.eraser;
  }

  double get _toolOpacity {
    switch (_activeTool) {
      case NoteTool.pencil:
        return 0.55;
      case NoteTool.highlighter:
        return 0.35;
      default:
        return 1.0;
    }
  }

  double get _toolWidth {
    switch (_activeTool) {
      case NoteTool.pencil:
        return _strokeWidth.clamp(1.5, 3.0);
      case NoteTool.highlighter:
        return _strokeWidth.clamp(8.0, 20.0);
      default:
        return _strokeWidth.clamp(2.0, 8.0);
    }
  }

  Future<void> _saveNote() async {
    if (_isSaving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_isInlineEditing) {
      _commitInlineText();
    }
    setState(() => _isSaving = true);
    try {
      final noteRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('note_folders')
          .doc(widget.folderId)
          .collection('notes')
          .doc(widget.noteId);
      await noteRef.update({
        'title': _noteTitle,
        'type': _noteType,
        'canvasHeight': _canvasHeight,
        'canvasWidth': _canvasWidth,
        'pageSpacing': _pageSpacing,
        'pdfUrl': _pdfUrl,
        'pdfName': _pdfName,
        'strokes': _strokes.map((e) => e.toMap()).toList(),
        'texts': _texts.map((e) => e.toMap()).toList(),
        'images': _images.map((e) => e.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _hasChanges = false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handlePopRequest() {
    if (_allowPop) return;
    () async {
      if (_isInlineEditing) {
        _commitInlineText();
      }
      if (_hasChanges) {
        await _saveNote();
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }();
  }

  Future<void> _renameNote() async {
    final controller = TextEditingController(text: _noteTitle);
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: tealAccent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    setState(() {
      _noteTitle = controller.text.trim();
      _hasChanges = true;
    });
  }

  void _startStroke(Offset localPosition, double scale, double yOffset) {
    if (!_isDrawingTool) return;
    final basePoint = Offset(localPosition.dx / scale, (localPosition.dy + yOffset) / scale);
    if (_activeTool == NoteTool.eraser) {
      _eraseAt(basePoint);
      return;
    }
    final stroke = NoteStroke(
      points: [basePoint],
      color: _activeColor.toARGB32(),
      width: _toolWidth,
      opacity: _toolOpacity,
      tool: _activeTool.name,
    );
    setState(() {
      _strokes.add(stroke);
      _activeStroke = stroke;
      _hasChanges = true;
    });
  }

  void _updateStroke(Offset localPosition, double scale, double yOffset) {
    if (!_isDrawingTool) return;
    final basePoint = Offset(localPosition.dx / scale, (localPosition.dy + yOffset) / scale);
    if (_activeTool == NoteTool.eraser) {
      _eraseAt(basePoint);
      return;
    }
    if (_activeStroke == null) return;
    setState(() {
      _activeStroke!.points.add(basePoint);
      _hasChanges = true;
    });
  }

  void _endStroke() {
    _activeStroke = null;
  }

  void _eraseAt(Offset basePoint) {
    const double radius = 18;
    final radiusSquared = radius * radius;
    setState(() {
      _strokes.removeWhere((stroke) {
        return stroke.points.any((point) {
          final dx = point.dx - basePoint.dx;
          final dy = point.dy - basePoint.dy;
          return dx * dx + dy * dy <= radiusSquared;
        });
      });
      _hasChanges = true;
    });
  }

  void _addTextAt(Offset localPosition, double scale, double yOffset) {
    final basePosition = Offset(localPosition.dx / scale, (localPosition.dy + yOffset) / scale);
    _beginInlineText(position: basePosition);
  }

  void _beginInlineText({required Offset position, NoteTextItem? existing, int? existingIndex}) {
    if (_isInlineEditing) {
      _commitInlineText();
    }
    setState(() {
      _isInlineEditing = true;
      _editingTextIndex = existingIndex;
      _inlineTextPosition = position;
      _inlineTextController.text = existing?.text ?? '';
      _textFontFamily = existing?.fontFamily ?? _textFontFamily;
      _textFontSize = existing?.fontSize ?? _textFontSize;
      if (existing != null) {
        _activeColor = Color(existing.color);
      }
    });
    FocusScope.of(context).requestFocus(_inlineTextFocusNode);
  }

  void _commitInlineText() {
    if (!_isInlineEditing) return;
    final text = _inlineTextController.text.trim();
    setState(() {
      if (text.isEmpty) {
        if (_editingTextIndex != null) {
          _texts.removeAt(_editingTextIndex!);
          _hasChanges = true;
        }
      } else {
        final item = NoteTextItem(
          id: _editingTextIndex != null ? _texts[_editingTextIndex!].id : const Uuid().v4(),
          text: text,
          x: _inlineTextPosition.dx,
          y: _inlineTextPosition.dy,
          fontSize: _textFontSize,
          fontFamily: _textFontFamily,
          color: _activeColor.toARGB32(),
        );
        if (_editingTextIndex != null) {
          _texts[_editingTextIndex!] = item;
        } else {
          _texts.add(item);
        }
        _hasChanges = true;
      }
      _inlineTextController.clear();
      _editingTextIndex = null;
      _isInlineEditing = false;
    });
  }


  Future<void> _addImage(double scale, double yOffset) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final result = await pickImageBytes(source: ImageSource.gallery, imageQuality: 80);
    if (result == null) return;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('notes')
        .child(user.uid)
        .child('images')
        .child('${widget.noteId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

    await storageRef.putData(result.bytes, SettableMetadata(contentType: 'image/jpeg'));

    final url = await storageRef.getDownloadURL();
    final baseX = 30 / scale;
    final baseY = (_noteType == 'pdf' ? _pdfScrollOffset + 80 : _scrollController.offset + 80) / scale;
    setState(() {
      _images.add(
        NoteImageItem(
          id: const Uuid().v4(),
          url: url,
          x: baseX,
          y: baseY,
          width: 180 / scale,
          height: 120 / scale,
        ),
      );
      _hasChanges = true;
    });
  }

  void _updateTextPosition(int index, Offset delta, double scale) {
    final item = _texts[index];
    setState(() {
      _texts[index] = item.copyWith(
        x: item.x + delta.dx / scale,
        y: item.y + delta.dy / scale,
      );
      _hasChanges = true;
    });
  }

  void _updateImagePosition(int index, Offset delta, double scale) {
    final item = _images[index];
    setState(() {
      _images[index] = item.copyWith(
        x: item.x + delta.dx / scale,
        y: item.y + delta.dy / scale,
      );
      _hasChanges = true;
    });
  }

  void _setDraggingAsset(bool value) {
    if (_isDraggingAsset == value) return;
    setState(() => _isDraggingAsset = value);
  }

  Future<bool> _ensureSpeechReady() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice notes are not supported on web yet.')),
        );
      }
      return false;
    }
    if (_speechAvailable) return true;
    if (_speechInitializing) return false;
    setState(() => _speechInitializing = true);
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Speech recognition error.')),
          );
        }
      },
    );
    if (mounted) {
      setState(() {
        _speechAvailable = available;
        _speechInitializing = false;
      });
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition is not available on this device.')),
        );
      }
    }
    return available;
  }

  Future<bool> _chargeForListening() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    bool allowed = false;
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final data = snapshot.data() ?? <String, dynamic>{};
      final int seshMinutes = (data['seshMinutes'] as num?)?.toInt() ?? 0;
      if (seshMinutes < 1) {
        allowed = false;
        return;
      }
      transaction.update(userRef, {'seshMinutes': FieldValue.increment(-1)});
      allowed = true;
    });
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need at least 1 sesh to use voice notes.')),
      );
    }
    return allowed;
  }

  void _appendSpeechText(String text) {
    if (!_isInlineEditing) {
      _beginInlineText(position: _inlineTextPosition);
    }
    final current = _inlineTextController.text;
    final separator = current.isEmpty ? '' : ' ';
    _inlineTextController.text = '$current$separator$text';
    _inlineTextController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inlineTextController.text.length),
    );
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    final ready = await _ensureSpeechReady();
    if (!ready) return;
    final paid = await _chargeForListening();
    if (!paid) return;

    if (_activeTool != NoteTool.text) {
      _selectTool(NoteTool.text);
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.trim().isEmpty) return;
        _appendSpeechText(result.recognizedWords.trim());
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _editTextItem(int index) {
    final item = _texts[index];
    _beginInlineText(position: Offset(item.x, item.y), existing: item, existingIndex: index);
  }

  Future<Uint8List> _exportCanvasPdfBytes() async {
    final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('Canvas not ready');
    }
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    final document = PdfDocument();
    document.pageSettings.margins.all = 0;
    document.pageSettings.size = Size(image.width.toDouble(), image.height.toDouble());
    final page = document.pages.add();
    page.graphics.drawImage(
      PdfBitmap(pngBytes),
      Rect.fromLTWH(0, 0, page.size.width, page.size.height),
    );
    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  int _pageIndexForY(double y, List<double> pageTops, List<double> pageHeights, double spacing) {
    for (int i = 0; i < pageTops.length; i++) {
      final top = pageTops[i];
      final bottom = top + pageHeights[i];
      if (y >= top && y <= bottom) {
        return i;
      }
      if (y < top) {
        return i;
      }
      if (y < bottom + spacing) {
        return i;
      }
    }
    return pageTops.length - 1;
  }

  Color _flattenColor(Color color, double opacity) {
    if (opacity >= 0.98) return color;
    final blend = Color.lerp(color, Colors.white, 1 - opacity) ?? color;
    return blend;
  }

  int _componentTo255(double value) {
    final component = (value * 255).round();
    if (component < 0) return 0;
    if (component > 255) return 255;
    return component;
  }

  PdfColor _pdfColorFrom(Color color) {
    return PdfColor(
      _componentTo255(color.r),
      _componentTo255(color.g),
      _componentTo255(color.b),
    );
  }

  Future<Uint8List> _exportPdfAnnotationBytes() async {
    if (_pdfUrl == null) {
      return _exportCanvasPdfBytes();
    }
    final pdfBytes = await _loadStorageBytes(_pdfUrl!);
    if (pdfBytes == null) {
      return _exportCanvasPdfBytes();
    }
    final document = PdfDocument(inputBytes: pdfBytes);
    final baseWidth = _canvasWidth;
    final spacing = _pageSpacing;
    final pageTops = <double>[];
    final pageHeights = <double>[];
    double currentTop = 0;
    for (int i = 0; i < document.pages.count; i++) {
      final page = document.pages[i];
      final displayHeight = page.size.height * (baseWidth / page.size.width);
      pageTops.add(currentTop);
      pageHeights.add(displayHeight);
      currentTop += displayHeight + spacing;
    }

    for (final stroke in _strokes) {
      for (int i = 1; i < stroke.points.length; i++) {
        final p1 = stroke.points[i - 1];
        final p2 = stroke.points[i];
        final pageIndex = _pageIndexForY(p1.dy, pageTops, pageHeights, spacing);
        if (_pageIndexForY(p2.dy, pageTops, pageHeights, spacing) != pageIndex) {
          continue;
        }
        final page = document.pages[pageIndex];
        final pageTop = pageTops[pageIndex];
        final scale = page.size.width / baseWidth;
        final color = _flattenColor(Color(stroke.color), stroke.opacity);
        final pen = PdfPen(
          _pdfColorFrom(color),
          width: stroke.width * scale,
        );
        final dx1 = p1.dx * scale;
        final dy1 = (p1.dy - pageTop) * scale;
        final dx2 = p2.dx * scale;
        final dy2 = (p2.dy - pageTop) * scale;
        page.graphics.drawLine(pen, Offset(dx1, dy1), Offset(dx2, dy2));
      }
    }

    for (final text in _texts) {
      final pageIndex = _pageIndexForY(text.y, pageTops, pageHeights, spacing);
      final page = document.pages[pageIndex];
      final pageTop = pageTops[pageIndex];
      final scale = page.size.width / baseWidth;
      final font = PdfStandardFont(PdfFontFamily.helvetica, text.fontSize * scale);
      final color = Color(text.color);
      final brush = PdfSolidBrush(_pdfColorFrom(color));
      page.graphics.drawString(
        text.text,
        font,
        brush: brush,
        bounds: Rect.fromLTWH(text.x * scale, (text.y - pageTop) * scale, page.size.width, page.size.height),
      );
    }

    for (final image in _images) {
      try {
        final imageBytes = await _loadStorageBytes(image.url);
        if (imageBytes == null) continue;
        final pdfImage = PdfBitmap(imageBytes);
        final pageIndex = _pageIndexForY(image.y, pageTops, pageHeights, spacing);
        final page = document.pages[pageIndex];
        final pageTop = pageTops[pageIndex];
        final scale = page.size.width / baseWidth;
        final rect = Rect.fromLTWH(
          image.x * scale,
          (image.y - pageTop) * scale,
          image.width * scale,
          image.height * scale,
        );
        page.graphics.drawImage(pdfImage, rect);
      } catch (_) {}
    }

    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  Future<Uint8List> _exportPdfBytes() async {
    if (_noteType == 'pdf') {
      return _exportPdfAnnotationBytes();
    }
    return _exportCanvasPdfBytes();
  }

  Future<void> _exportToFile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final bytes = await _exportPdfBytes();
      final fileName = '${_safeFileName(_noteTitle)}.pdf';
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('note_exports')
          .child(user.uid)
          .child('${widget.noteId}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await storageRef.putData(
        bytes,
        SettableMetadata(
          contentType: 'application/pdf',
          contentDisposition: 'attachment; filename="$fileName"',
        ),
      );
      final url = await storageRef.getDownloadURL();
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
      if (mounted) {
        final message = launched ? 'PDF ready to download.' : 'PDF export ready (open the link manually).';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not export PDF.')));
      }
    }
  }

  Future<void> _shareToVault() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final subjectController = TextEditingController(text: _folderTitle ?? '');
    final yearController = TextEditingController(text: DateTime.now().year.toString());
    String selectedType = 'Notes';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: cardColor,
          title: const Text('Add to Vault', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Subject / Course code',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: backgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: yearController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Year',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: backgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedType,
                  dropdownColor: backgroundColor,
                  isExpanded: true,
                  items: ['Notes', 'Past Paper', 'Question Bank']
                      .map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selectedType = value ?? selectedType),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    _showLoading('Uploading to Vault...');
    try {
      final bytes = await _exportPdfBytes();
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('vault')
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await storageRef.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
      final url = await storageRef.getDownloadURL();
      await FirebaseFirestore.instance.collection('vault').add({
        'userId': user.uid,
        'subject': subjectController.text.trim().toUpperCase(),
        'year': yearController.text.trim(),
        'type': selectedType,
        'fileUrl': url,
        'stars': 0,
        'starredBy': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Vault.')));
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vault upload failed.')));
      }
    }
  }

  Future<void> _sellOnMarketplace() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final titleController = TextEditingController(text: _noteTitle);
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final rawPrice = priceController.text.replaceAll(RegExp(r'[^0-9]'), '');
          final basePrice = int.tryParse(rawPrice) ?? 0;
          final platformFee = (basePrice * 0.10).round();
          final displayPrice = basePrice + platformFee;
          return AlertDialog(
            backgroundColor: cardColor,
            title: const Text('Sell on marketplace', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Listing title',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Description',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Price (ZAR)',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seshly stores your notes and releases them after payment.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Buyer pays R$displayPrice (includes 10% Seshly fee). You earn R$basePrice.',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('List')),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final basePrice = int.tryParse(priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (basePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price.')));
      return;
    }
    final platformFee = (basePrice * 0.10).round();
    final displayPrice = basePrice + platformFee;

    _showLoading('Creating listing...');
    try {
      final bytes = await _exportPdfBytes();
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('marketplace_items')
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await storageRef.putData(bytes, SettableMetadata(contentType: 'application/pdf'));
      final fileUrl = await storageRef.getDownloadURL();

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final sellerName = (userData['fullName'] ?? userData['displayName'] ?? 'Student').toString();

      await FirebaseFirestore.instance.collection('marketplace_items').add({
        'title': titleController.text.trim(),
        'description': descriptionController.text.trim(),
        'price': displayPrice,
        'currency': 'ZAR',
        'category': 'Notes',
        'isDigital': true,
        'sellerId': user.uid,
        'sellerName': sellerName,
        'imageUrl': null,
        'status': 'active',
        'fileUrl': fileUrl,
        'fileName': '${_noteTitle.replaceAll(' ', '_')}.pdf',
        'fileType': 'pdf',
        'sellerPrice': basePrice,
        'platformFee': platformFee,
        'priceIncludesFee': true,
        'listingType': 'notes',
        'fulfillment': 'seshly',
        'sourceNoteId': widget.noteId,
        'sourceFolderId': widget.folderId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listing created.')));
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create listing.')));
      }
    }
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: cardColor,
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C09E))),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  void _showShareMenu() {
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
            const Text('Share notes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            _ActionTile(
              icon: Icons.download_rounded,
              title: 'Export PDF',
              subtitle: 'Save to device storage.',
              onTap: () {
                Navigator.pop(context);
                _exportToFile();
              },
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.cloud_upload_outlined,
              title: 'Add to Vault',
              subtitle: 'Share for free with the community.',
              onTap: () {
                Navigator.pop(context);
                _shareToVault();
              },
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.storefront_outlined,
              title: 'Sell on marketplace',
              subtitle: 'Create a paid listing from this note.',
              onTap: () {
                Navigator.pop(context);
                _sellOnMarketplace();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBar(double scale, double yOffset) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ToolButton(
                  icon: Icons.edit_rounded,
                  label: 'Pen',
                  selected: _activeTool == NoteTool.pen,
                  onTap: () => _selectTool(NoteTool.pen),
                ),
                _ToolButton(
                  icon: Icons.create_outlined,
                  label: 'Pencil',
                  selected: _activeTool == NoteTool.pencil,
                  onTap: () => _selectTool(NoteTool.pencil),
                ),
                _ToolButton(
                  icon: Icons.highlight_outlined,
                  label: 'Highlight',
                  selected: _activeTool == NoteTool.highlighter,
                  onTap: () => _selectTool(NoteTool.highlighter),
                ),
                _ToolButton(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Eraser',
                  selected: _activeTool == NoteTool.eraser,
                  onTap: () => _selectTool(NoteTool.eraser),
                ),
                _ToolButton(
                  icon: Icons.text_fields,
                  label: 'Text',
                  selected: _activeTool == NoteTool.text,
                  onTap: () => _selectTool(NoteTool.text),
                ),
                _ToolButton(
                  icon: Icons.pan_tool_outlined,
                  label: 'Move',
                  selected: _activeTool == NoteTool.move,
                  onTap: () => _selectTool(NoteTool.move),
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  selected: false,
                  onTap: () => _addImage(scale, yOffset),
                ),
                _ToolButton(
                  icon: _isListening ? Icons.mic : Icons.mic_none,
                  label: _isListening ? 'Listening' : 'Listen',
                  selected: _isListening,
                  activeColor: Colors.redAccent,
                  onTap: _toggleListening,
                ),
                _ToolButton(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  selected: false,
                  onTap: _showShareMenu,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_activeTool != NoteTool.eraser && _activeTool != NoteTool.move && _activeTool != NoteTool.text)
            Row(
              children: [
                const Text('Ink', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _strokeWidth,
                    min: 2,
                    max: 16,
                    activeColor: tealAccent,
                    onChanged: (value) => setState(() => _strokeWidth = value),
                  ),
                ),
              ],
            ),
          if (_activeTool != NoteTool.eraser && _activeTool != NoteTool.move)
            Row(
              children: _noteColors.map((color) {
                final bool selected = _activeColor.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _activeColor = color),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                    ),
                  ),
                );
              }).toList(),
            ),
          if (_activeTool == NoteTool.text) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white.withValues(alpha: 0.5), size: 16),
                  const SizedBox(width: 6),
                  const Text('Tap on the page to add text.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Font', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _textFontFamily,
                      dropdownColor: backgroundColor,
                      isExpanded: true,
                      onChanged: (value) => setState(() => _textFontFamily = value ?? _textFontFamily),
                      items: _fontFamilies
                          .map((font) => DropdownMenuItem<String>(
                                value: font,
                                child: Text(font, style: const TextStyle(color: Colors.white)),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _textFontSize,
                    min: 12,
                    max: 34,
                    divisions: 11,
                    label: _textFontSize.toStringAsFixed(0),
                    activeColor: tealAccent,
                    onChanged: (value) => setState(() => _textFontSize = value),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Voice notes cost 1 sesh per session.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCanvasEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayWidth = constraints.maxWidth - 30;
        final scale = displayWidth / _canvasWidth;
        final displayHeight = _canvasHeight * scale;
        return Column(
          children: [
            _buildToolBar(scale, 0),
            const SizedBox(height: 12),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.pixels > notification.metrics.maxScrollExtent - 200) {
                    setState(() {
                      _canvasHeight += 600;
                      _hasChanges = true;
                    });
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: _activeTool == NoteTool.move && !_isDraggingAsset
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: Center(
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: displayWidth,
                          height: displayHeight,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F2E8),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 6)),
                            ],
                          ),
                          child: Stack(
                            children: [
                              CustomPaint(
                                size: Size(displayWidth, displayHeight),
                                painter: _PaperPainter(),
                              ),
                              CustomPaint(
                                size: Size(displayWidth, displayHeight),
                                painter: _StrokePainter(strokes: _strokes, scale: scale, yOffset: 0),
                              ),
                              ..._buildImageWidgets(scale, 0),
                              ..._buildTextWidgets(scale, 0),
                              Positioned.fill(
                                child: IgnorePointer(
                                  ignoring: _isInlineEditing || !(_isDrawingTool || _activeTool == NoteTool.text),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onPanStart: (details) => _startStroke(details.localPosition, scale, 0),
                                    onPanUpdate: (details) => _updateStroke(details.localPosition, scale, 0),
                                    onPanEnd: (_) => _endStroke(),
                                    onTapUp: (details) {
                                      if (_activeTool == NoteTool.text) {
                                        _addTextAt(details.localPosition, scale, 0);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              _buildInlineTextEditor(scale, 0, displayWidth, displayHeight),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInlineTextEditor(double scale, double yOffset, double maxWidth, double maxHeight) {
    if (!_isInlineEditing) return const SizedBox.shrink();
    final double maxLeft = maxWidth - 180.0;
    final double maxTop = maxHeight - 80.0;
    final double left = (_inlineTextPosition.dx * scale).clamp(12.0, maxLeft < 12.0 ? 12.0 : maxLeft).toDouble();
    final double top = (_inlineTextPosition.dy * scale - yOffset).clamp(12.0, maxTop < 12.0 ? 12.0 : maxTop).toDouble();
    final double maxFieldWidth = maxWidth - left - 24;

    return Positioned(
      left: left,
      top: top,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxFieldWidth, minWidth: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: TextField(
            controller: _inlineTextController,
            focusNode: _inlineTextFocusNode,
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: tealAccent,
            style: TextStyle(
              color: _activeColor,
              fontSize: _textFontSize * scale,
              fontFamily: _textFontFamily,
              height: 1.2,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _commitInlineText(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTextWidgets(double scale, double yOffset) {
    return _texts.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      if (_editingTextIndex == index && _isInlineEditing) {
        return const SizedBox.shrink();
      }
      return Positioned(
        left: item.x * scale,
        top: item.y * scale - yOffset,
        child: GestureDetector(
          onDoubleTap: () => _editTextItem(index),
          onLongPress: () {
            setState(() {
              _texts.removeAt(index);
              _hasChanges = true;
            });
          },
          onPanStart: _activeTool == NoteTool.move ? (_) => _setDraggingAsset(true) : null,
          onPanUpdate: (details) {
            if (_activeTool != NoteTool.move) return;
            _updateTextPosition(index, details.delta, scale);
          },
          onPanEnd: _activeTool == NoteTool.move ? (_) => _setDraggingAsset(false) : null,
          onPanCancel: _activeTool == NoteTool.move ? () => _setDraggingAsset(false) : null,
          child: Text(
            item.text,
            style: TextStyle(
              color: Color(item.color),
              fontSize: item.fontSize * scale,
              fontFamily: item.fontFamily,
              height: 1.2,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildImageWidgets(double scale, double yOffset) {
    return _images.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      return Positioned(
        left: item.x * scale,
        top: item.y * scale - yOffset,
        child: GestureDetector(
          onTapDown: (_) {
            if (_activeTool != NoteTool.move) {
              _selectTool(NoteTool.move);
            }
          },
          onLongPress: () {
            setState(() {
              _images.removeAt(index);
              _hasChanges = true;
            });
          },
          onPanStart: _activeTool == NoteTool.move ? (_) => _setDraggingAsset(true) : null,
          onPanUpdate: (details) {
            if (_activeTool != NoteTool.move) return;
            _updateImagePosition(index, details.delta, scale);
          },
          onPanEnd: _activeTool == NoteTool.move ? (_) => _setDraggingAsset(false) : null,
          onPanCancel: _activeTool == NoteTool.move ? () => _setDraggingAsset(false) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              item.url,
              width: item.width * scale,
              height: item.height * scale,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildPdfEditor() {
    if (_pdfUrl == null || _pdfUrl!.isEmpty) {
      return const Center(
        child: Text('PDF not available.', style: TextStyle(color: Colors.white54)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayWidth = constraints.maxWidth - 20;
        final scale = displayWidth / _canvasWidth;
        return Column(
          children: [
            _buildToolBar(scale, _pdfScrollOffset),
            const SizedBox(height: 12),
            Expanded(
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis == Axis.vertical) {
                        setState(() => _pdfScrollOffset = notification.metrics.pixels);
                      }
                      return false;
                    },
                    child: AbsorbPointer(
                      absorbing: _activeTool != NoteTool.move,
                      child: SfPdfViewer.network(
                        _pdfUrl ?? '',
                        controller: _pdfController,
                        enableDoubleTapZooming: false,
                        maxZoomLevel: 1,
                        pageSpacing: _pageSpacing,
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: Size(displayWidth, constraints.maxHeight),
                    painter: _StrokePainter(strokes: _strokes, scale: scale, yOffset: _pdfScrollOffset),
                  ),
                  ..._buildImageWidgets(scale, _pdfScrollOffset),
                  ..._buildTextWidgets(scale, _pdfScrollOffset),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _isInlineEditing || !(_isDrawingTool || _activeTool == NoteTool.text),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (details) => _startStroke(details.localPosition, scale, _pdfScrollOffset),
                        onPanUpdate: (details) => _updateStroke(details.localPosition, scale, _pdfScrollOffset),
                        onPanEnd: (_) => _endStroke(),
                        onTapUp: (details) {
                          if (_activeTool == NoteTool.text) {
                            _addTextAt(details.localPosition, scale, _pdfScrollOffset);
                          }
                        },
                      ),
                    ),
                  ),
                  _buildInlineTextEditor(scale, _pdfScrollOffset, displayWidth, constraints.maxHeight),
                ],
              ),
            ),
            if (_pdfName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Source: $_pdfName', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F142B),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00C09E))),
      );
    }

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handlePopRequest();
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handlePopRequest,
          ),
          title: GestureDetector(
            onTap: _renameNote,
            child: Row(
              children: [
                Flexible(
                  child: Text(_noteTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, color: Colors.white54, size: 16),
              ],
            ),
          ),
          actions: [
            IconButton(
              onPressed: _isSaving ? null : _saveNote,
              icon: const Icon(Icons.save_outlined, color: Colors.white70),
            ),
            IconButton(
              onPressed: _showShareMenu,
              icon: const Icon(Icons.ios_share_outlined, color: Colors.white70),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: _noteType == 'pdf' ? _buildPdfEditor() : _buildCanvasEditor(),
        ),
      ),
    );
  }
}
