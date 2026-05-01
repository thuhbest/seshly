import 'package:flutter/material.dart';
import 'package:seshly/services/app_analytics_service.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/sesh_ai_api.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class SeshAIHintModal extends StatefulWidget {
  const SeshAIHintModal({super.key});

  @override
  State<SeshAIHintModal> createState() => _SeshAIHintModalState();
}

class _SeshAIHintModalState extends State<SeshAIHintModal> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);
  final _questionController = TextEditingController();
  final _attemptController = TextEditingController();
  final _api = SeshAiApi();

  int hintsRemaining = 2; // Rate-limited per practice session
  bool _isAnalyzing = false;
  String? _currentHint;

  void _requestHint() async {
    if (hintsRemaining <= 0) return;
    final question = _questionController.text.trim();
    final attempt = _attemptController.text.trim();
    if (question.isEmpty || attempt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add the question and your attempt first.')),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _currentHint = null;
    });

    try {
      final response = await _api.practiceCoach(
        questionId: DateTime.now().millisecondsSinceEpoch.toString(),
        questionText: question,
        studentAttemptText: attempt,
      );
      setState(() {
        _isAnalyzing = false;
        _currentHint = response['nextHint']?.toString();
        hintsRemaining--;
      });
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'practice_hint',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'practice_hint',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'practice_hint',
      );
      setState(() => _isAnalyzing = false);
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        AppErrorService.instance.userMessageFor(
          error,
          fallback: 'Hint failed. Please try again.',
        ),
      );
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    _attemptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 30),
          _buildHintContent(),
          const SizedBox(height: 30),
          _buildActionArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: tealAccent),
            const SizedBox(width: 10),
            const Text("Sesh AI Nudge", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: tealAccent.withValues(alpha: 25), borderRadius: BorderRadius.circular(8)),
          child: Text("$hintsRemaining / 3 HINTS LEFT", style: TextStyle(color: tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildHintContent() {
    if (_isAnalyzing) {
      return Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFF00C09E)),
          const SizedBox(height: 16),
          Text("Analyzing your board...", style: TextStyle(color: Colors.white.withValues(alpha: 150))),
        ],
      );
    }

    if (_currentHint != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: backgroundColor.withValues(alpha: 128),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: tealAccent.withValues(alpha: 50)),
        ),
        child: Text(
          _currentHint!,
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5, fontStyle: FontStyle.italic),
        ),
      );
    }

    return Text(
      "Stuck? Sesh AI can look at your progress and give you a subtle nudge forward without giving the answer.",
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white.withValues(alpha: 100), fontSize: 13),
    );
  }

  Widget _buildActionArea() {
    bool canRequest = hintsRemaining > 0 && !_isAnalyzing;
    
    return Column(
      children: [
        TextField(
          controller: _questionController,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Paste the question here',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 80)),
            filled: true,
            fillColor: backgroundColor.withValues(alpha: 120),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _attemptController,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Describe your attempt',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 80)),
            filled: true,
            fillColor: backgroundColor.withValues(alpha: 120),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        const SizedBox(height: 15),
        PressableScale(
          onTap: canRequest ? _requestHint : null,
          borderRadius: BorderRadius.circular(15),
          pressedScale: 0.97,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 55,
            decoration: BoxDecoration(
              color: canRequest ? tealAccent : Colors.white10,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(
                canRequest ? "Request Hint" : "Out of Hints",
                style: TextStyle(color: canRequest ? backgroundColor : Colors.white24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("I'll figure it out", style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}
