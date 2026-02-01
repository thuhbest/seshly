import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:seshly/features/sesh/view/sesh_ai_chat_view.dart';

class SeshInputBox extends StatefulWidget {
  const SeshInputBox({super.key});

  @override
  State<SeshInputBox> createState() => _SeshInputBoxState();
}

class _SeshInputBoxState extends State<SeshInputBox> {
  final _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleAsk() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!mounted) return;
    setState(() => _isLoading = true);
    _controller.clear();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeshAiChatView(
          title: 'Sesh AI',
          subject: 'Sesh AI',
          initialMessage: text,
          autoSend: true,
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: tealAccent.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Ask Sesh Anything",
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(15),
            ),
            child: TextField(
              controller: _controller,
              style: GoogleFonts.spaceGrotesk(color: Colors.white),
              decoration: InputDecoration(
                hintText: "What do you need help with today?",
                hintStyle: GoogleFonts.spaceGrotesk(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleAsk,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _isLoading ? "Thinking..." : "Get AI Help",
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: const Color(0xFF0F142B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
