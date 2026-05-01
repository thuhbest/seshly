import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:seshly/features/sesh/view/archive_view.dart';
import 'package:seshly/features/sesh/view/sesh_ai_chat_view.dart';
import 'package:seshly/features/sesh/view/sesh_ai_threads_view.dart';
import 'package:seshly/services/app_analytics_service.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/sesh_ai_api.dart';
import 'package:seshly/theme/seshly_theme.dart';
import 'package:seshly/widgets/responsive.dart';

import '../widgets/sesh_feature_card.dart';
import '../widgets/sesh_input_box.dart';
import '../widgets/sesh_tab_bar.dart';

class SeshView extends StatefulWidget {
  const SeshView({super.key});

  @override
  State<SeshView> createState() => _SeshViewState();
}

class _SeshViewState extends State<SeshView> {
  String _selectedTab = 'Sesh Help';
  final _api = SeshAiApi();
  bool _busy = false;

  Future<String?> _uploadBytes(
    Uint8List bytes,
    String path,
    String contentType,
  ) async {
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
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
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
            initialMessage:
                'Explain this diagram or image in clear study-friendly terms.',
            initialAttachments: [url],
            autoSend: true,
          ),
        ),
      );
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'snap_study',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'snap_study',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'snap_study',
      );
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        AppErrorService.instance.userMessageFor(
          error,
          fallback: 'Snap & Study failed. Please try again.',
        ),
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
          const SnackBar(
            content: Text('Please sign in to create Smart Notes.'),
          ),
        );
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
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
              final topics =
                  (response['extractedTopics'] as List<dynamic>? ?? [])
                      .map((e) => e.toString())
                      .toList();
              final message = [
                'Smart notes ready.',
                if (topics.isNotEmpty) 'Topics: ${topics.join(', ')}',
                if (pdfUrl != null) 'Open the PDF from the top right button.',
              ].join('\n');
              return ChatActionResult(messages: [message], primaryUrl: pdfUrl);
            },
          ),
        ),
      );
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'smart_notes',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'smart_notes',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'smart_notes',
      );
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        AppErrorService.instance.userMessageFor(
          error,
          fallback: 'Smart Notes failed. Please try again.',
        ),
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
          const SnackBar(
            content: Text('Please sign in to generate a practice quiz.'),
          ),
        );
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
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
                  : questions.map((q) => '- ${q['question'] ?? ''}').join('\n');
              return ChatActionResult(
                messages: ['Here is your practice quiz:\n$questionText'],
              );
            },
          ),
        ),
      );
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'practice_quiz',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'practice_quiz',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'practice_quiz',
      );
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        AppErrorService.instance.userMessageFor(
          error,
          fallback: 'Practice Quiz failed. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeshlyPalette.background,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Padding(
              padding: pagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  _buildHeader(),
                  const SizedBox(height: 18),
                  SeshTabBar(
                    selectedTab: _selectedTab,
                    onTabChanged: (tab) => setState(() => _selectedTab = tab),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: ListView(
                        key: ValueKey(_selectedTab),
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [_buildActiveView()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final button = FilledButton.tonalIcon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SeshAiThreadsView()),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            foregroundColor: SeshlyPalette.textPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
          label: const Text(
            'Threads',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        );

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sesh',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: SeshlyPalette.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ask Sesh, run quick study tools, and keep saved work close.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        );

        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: button),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            button,
          ],
        );
      },
    );
  }

  Widget _buildActiveView() {
    switch (_selectedTab) {
      case 'Sesh Help':
        return _buildSeshHelpDashboard();
      case 'Notes & Archive':
        return _buildNotesArchiveDashboard();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSeshHelpDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SeshInputBox(),
        const SizedBox(height: 18),
        SeshFeatureCard(
          title: 'Snap & Study',
          description:
              'Take photos of diagrams, whiteboards, or textbook pages and get AI explanations fast.',
          buttonText: _busy ? 'Working...' : 'Use Image',
          icon: Icons.camera_alt_outlined,
          onTap: _busy ? null : _handleSnapStudy,
        ),
        SeshFeatureCard(
          title: 'Practice Quiz',
          description:
              'Generate a quiz from your study material and test your understanding quickly.',
          buttonText: _busy ? 'Working...' : 'Start Quiz',
          icon: Icons.track_changes_outlined,
          onTap: _busy ? null : _handlePracticeQuiz,
        ),
        SeshFeatureCard(
          title: 'Smart Notes',
          description:
              'Convert a PDF into clean study notes without leaving Sesh Help.',
          buttonText: _busy ? 'Working...' : 'Create Notes',
          icon: Icons.description_outlined,
          onTap: _busy ? null : _handleSmartNotes,
        ),
        const SizedBox(height: 16),
        _NotesLaneCard(
          onOpenArchive: () => setState(() => _selectedTab = 'Notes & Archive'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildNotesArchiveDashboard() {
    return const ArchiveView();
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF07111F), Color(0xFF0E1930), Color(0xFF08131F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            right: -70,
            child: _glow(const Color(0xFF6FF2D4), 280),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: _glow(const Color(0xFFF4C96C), 260),
          ),
          Positioned(
            top: 200,
            left: 12,
            child: _glow(const Color(0xFF41C7FF), 170),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _NotesLaneCard extends StatelessWidget {
  const _NotesLaneCard({required this.onOpenArchive});

  final VoidCallback onOpenArchive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool stacked = constraints.maxWidth < 720;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: SeshlyPalette.surfaceRaised.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _NotesLaneCardBody(),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: onOpenArchive,
                        child: const Text('Open Notes & Archive'),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Expanded(child: _NotesLaneCardBody()),
                    const SizedBox(width: 16),
                    FilledButton.tonal(
                      onPressed: onOpenArchive,
                      child: const Text('Open Notes & Archive'),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _NotesLaneCardBody extends StatelessWidget {
  const _NotesLaneCardBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: SeshlyPalette.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.edit_note_rounded, color: SeshlyPalette.gold),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Need to save or capture work?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Move to Notes & Archive for folders, lecture capture, PDFs, and long-form study material.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
