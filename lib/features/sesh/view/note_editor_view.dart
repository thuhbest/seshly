import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:uuid/uuid.dart';

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

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? tealAccent : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? tealAccent : Colors.white12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? const Color(0xFF0F142B) : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF0F142B) : Colors.white70,
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
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey _canvasKey = GlobalKey();
  final List<NoteStroke> _strokes = [];
  final List<NoteTextItem> _texts = [];
  final List<NoteImageItem> _images = [];
  NoteStroke? _activeStroke;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;
  bool _allowPop = false;
  double _canvasHeight = 1400;
  double _canvasWidth = 360;
  double _pageSpacing = 16;
  double _pdfScrollOffset = 0;
  String _noteTitle = 'Note';
  String _noteType = 'canvas';
  String? _pdfUrl;
  String? _pdfName;
  String? _folderTitle;
  NoteTool _activeTool = NoteTool.pen;
  Color _activeColor = const Color(0xFF1F1F1F);
  double _strokeWidth = 3.0;

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

  @override
  void initState() {
    super.initState();
    _loadNote();
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
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

  Future<void> _addTextAt(Offset localPosition, double scale, double yOffset) async {
    final basePosition = Offset(localPosition.dx / scale, (localPosition.dy + yOffset) / scale);
    final newItem = await _showTextDialog(position: basePosition);
    if (newItem == null) return;
    setState(() {
      _texts.add(newItem);
      _hasChanges = true;
    });
  }

  Future<NoteTextItem?> _showTextDialog({required Offset position, NoteTextItem? existing}) async {
    final controller = TextEditingController(text: existing?.text ?? '');
    String fontFamily = existing?.fontFamily ?? _fontFamilies.first;
    double fontSize = existing?.fontSize ?? 16;
    Color color = existing != null ? Color(existing.color) : _activeColor;
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: cardColor,
            title: Text(existing == null ? 'Add text' : 'Edit text', style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type here...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: backgroundColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Font', style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        value: fontFamily,
                        isExpanded: true,
                        dropdownColor: backgroundColor,
                        onChanged: (value) => setDialogState(() => fontFamily = value ?? fontFamily),
                        items: _fontFamilies
                            .map((font) => DropdownMenuItem<String>(
                                  value: font,
                                  child: Text(font, style: const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Size', style: TextStyle(color: Colors.white70)),
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 12,
                        max: 32,
                        divisions: 10,
                        label: fontSize.toStringAsFixed(0),
                        activeColor: tealAccent,
                        onChanged: (value) => setDialogState(() => fontSize = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: _noteColors.map((colorOption) {
                    final bool selected = colorOption.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () => setDialogState(() => color = colorOption),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: colorOption,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) return null;
    return NoteTextItem(
      id: existing?.id ?? const Uuid().v4(),
      text: controller.text.trim(),
      x: existing?.x ?? position.dx,
      y: existing?.y ?? position.dy,
      fontSize: fontSize,
      fontFamily: fontFamily,
      color: color.toARGB32(),
    );
  }

  Future<void> _addImage(double scale, double yOffset) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('notes')
        .child(user.uid)
        .child('images')
        .child('${widget.noteId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

    if (kIsWeb) {
      await storageRef.putData(await image.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
    } else {
      await storageRef.putFile(File(image.path));
    }

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

  Future<void> _editTextItem(int index) async {
    final item = _texts[index];
    final updated = await _showTextDialog(position: Offset(item.x, item.y), existing: item);
    if (updated == null) return;
    setState(() {
      _texts[index] = updated;
      _hasChanges = true;
    });
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
    final file = await DefaultCacheManager().getSingleFile(_pdfUrl!);
    final pdfBytes = await file.readAsBytes();
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
        final imageFile = await DefaultCacheManager().getSingleFile(image.url);
        final imageBytes = await imageFile.readAsBytes();
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
      final bytes = await _exportPdfBytes();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_noteTitle.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF exported to device storage.')));
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
      builder: (context) => AlertDialog(
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
              decoration: InputDecoration(
                hintText: 'Price (ZAR)',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('List')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final price = int.tryParse(priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid price.')));
      return;
    }

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
        'price': price,
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
                  onTap: () => setState(() => _activeTool = NoteTool.pen),
                ),
                _ToolButton(
                  icon: Icons.create_outlined,
                  label: 'Pencil',
                  selected: _activeTool == NoteTool.pencil,
                  onTap: () => setState(() => _activeTool = NoteTool.pencil),
                ),
                _ToolButton(
                  icon: Icons.highlight_outlined,
                  label: 'Highlight',
                  selected: _activeTool == NoteTool.highlighter,
                  onTap: () => setState(() => _activeTool = NoteTool.highlighter),
                ),
                _ToolButton(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Eraser',
                  selected: _activeTool == NoteTool.eraser,
                  onTap: () => setState(() => _activeTool = NoteTool.eraser),
                ),
                _ToolButton(
                  icon: Icons.text_fields,
                  label: 'Text',
                  selected: _activeTool == NoteTool.text,
                  onTap: () => setState(() => _activeTool = NoteTool.text),
                ),
                _ToolButton(
                  icon: Icons.pan_tool_outlined,
                  label: 'Move',
                  selected: _activeTool == NoteTool.move,
                  onTap: () => setState(() => _activeTool = NoteTool.move),
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  selected: false,
                  onTap: () => _addImage(scale, yOffset),
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
          if (_activeTool == NoteTool.text)
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
                  physics: _activeTool == NoteTool.move ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
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
                                  ignoring: !(_isDrawingTool || _activeTool == NoteTool.text),
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

  List<Widget> _buildTextWidgets(double scale, double yOffset) {
    return _texts.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
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
          onPanUpdate: (details) => _updateTextPosition(index, details.delta, scale),
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
          onLongPress: () {
            setState(() {
              _images.removeAt(index);
              _hasChanges = true;
            });
          },
          onPanUpdate: (details) => _updateImagePosition(index, details.delta, scale),
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
                      ignoring: !(_isDrawingTool || _activeTool == NoteTool.text),
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
      onPopInvoked: (didPop) {
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
