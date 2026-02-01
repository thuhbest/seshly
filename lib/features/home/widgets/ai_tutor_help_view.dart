import 'package:flutter/material.dart';
import 'package:seshly/services/sesh_ai_api.dart';

class AiTutorHelpView extends StatefulWidget {
  const AiTutorHelpView({
    super.key,
    required this.subject,
    required this.question,
    required this.details,
    this.attachmentUrl,
  });

  final String subject;
  final String question;
  final String details;
  final String? attachmentUrl;

  @override
  State<AiTutorHelpView> createState() => _AiTutorHelpViewState();
}

class _AiTutorHelpViewState extends State<AiTutorHelpView> {
  final _api = SeshAiApi();
  final _askController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _askController.dispose();
    super.dispose();
  }

  Future<void> _askSeshAi() async {
    final ask = _askController.text.trim();
    if (ask.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final prompt = [
        'Question: ${widget.question}',
        if (widget.details.trim().isNotEmpty) 'Details: ${widget.details}',
        'Student ask: $ask',
      ].join('\n');

      final response = await _api.chatSocratic(
        message: prompt,
        subject: widget.subject,
        attachments: widget.attachmentUrl != null && widget.attachmentUrl!.trim().isNotEmpty
            ? [widget.attachmentUrl!.trim()]
            : null,
      );

      final reply = (response['replyText'] ?? '').toString().trim();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1E243A),
          title: const Text('Sesh AI', style: TextStyle(color: Colors.white)),
          content: Text(
            reply.isEmpty ? 'Sesh AI responded.' : reply,
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sesh AI failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardBg = Color(0xFF1E243A);

    return Column(
      children: [
        // --- Ask Sesh Box ---
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: tealAccent.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: tealAccent.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _circleIcon(Icons.auto_awesome),
                  const SizedBox(width: 15),
                  const Text("Ask Sesh AI", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 15),
              const Text(
                "Get instant help with this question. Sesh can break down the problem, explain concepts, and guide you step-by-step.",
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _askController,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "What part are you stuck on?",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF12182D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              _fullWidthButton(
                _isLoading ? "Thinking..." : "Get Help from Sesh",
                isPrimary: true,
                onTap: _isLoading ? null : _askSeshAi,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // --- Human Help Box ---
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Need Human Help?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text("Connect with a verified tutor who can explain this in detail", style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),
              _fullWidthButton("Find a Tutor", icon: Icons.person_add_alt_1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF00C09E).withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Icon(icon, color: const Color(0xFF00C09E), size: 20),
    );
  }

  Widget _fullWidthButton(String label, {bool isPrimary = false, IconData? icon, VoidCallback? onTap}) {
    const Color tealAccent = Color(0xFF00C09E);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? tealAccent : Colors.white.withValues(alpha: 0.05),
          foregroundColor: isPrimary ? const Color(0xFF0F142B) : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: isPrimary ? null : BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, color: Colors.white70, size: 18), const SizedBox(width: 8)],
            if (isPrimary) ...[const Icon(Icons.auto_awesome, color: Color(0xFF0F142B), size: 16), const SizedBox(width: 8)],
            Text(label, style: TextStyle(color: isPrimary ? const Color(0xFF0F142B) : Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
