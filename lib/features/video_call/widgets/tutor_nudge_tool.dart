import 'package:flutter/material.dart';

class TutorNudgeTool extends StatefulWidget {
  final String studentName;
  final String studentId;

  const TutorNudgeTool({
    super.key,
    required this.studentName,
    required this.studentId,
  });

  @override
  State<TutorNudgeTool> createState() => _TutorNudgeToolState();
}

class _TutorNudgeToolState extends State<TutorNudgeTool> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  final List<String> _quickNudges = [
    "Check your signs (+/-)",
    "Try Step 2 again",
    "Show your working",
    "Explain this part",
  ];

  String? _selectedNudge;
  final bool _isAIGenerating = false;

  void _sendNudge(String message) {
    // Logic: Send message to specific student via WebSocket/Firebase
    debugPrint("Nudging ${widget.studentName}: $message");
    Navigator.pop(context);
    
    // Tactile Feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: tealAccent,
        content: Text("Nudge sent to ${widget.studentName}", 
          style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold)),
      ),
    );
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 25),
          
          _sectionLabel("SESH AI SUGGESTION"),
          _buildAISuggestionBox(),
          
          const SizedBox(height: 25),
          _sectionLabel("QUICK NUDGES"),
          _buildNudgeGrid(),
          
          const SizedBox(height: 30),
          _buildCustomAction(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: tealAccent.withValues(alpha: 50),
          child: Text(widget.studentName[0], 
            style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Nudge ${widget.studentName}", 
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Text("Guide them without giving the answer", 
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        const Spacer(),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white24),
        ),
      ],
    );
  }

  Widget _buildAISuggestionBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tealAccent.withValues(alpha: 20),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tealAccent.withValues(alpha: 40)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: tealAccent, size: 16),
              const SizedBox(width: 8),
              const Text("SESH AI ANALYST", 
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isAIGenerating)
                const SizedBox(width: 12, height: 12, 
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            "“Student seems to be struggling with the integration constant (C). Suggest a check there.”",
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _sendNudge("Check your integration constant"),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: tealAccent, borderRadius: BorderRadius.circular(10)),
              child: Text("Send AI Suggestion", 
                style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNudgeGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _quickNudges.map((nudge) => GestureDetector(
        onTap: () => _sendNudge(nudge),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 10)),
          ),
          child: Text(nudge, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      )).toList(),
    );
  }

  Widget _buildCustomAction() {
    return Row(
      children: [
        Expanded(
          child: _TactileActionBtn(
            onTap: () {
              Navigator.pop(context);
              // Logic: Tutor enters student board
              debugPrint("Jumping into ${widget.studentName}'s board");
            },
            icon: Icons.edit_note_rounded,
            label: "Jump In",
            color: Colors.white10,
            textColor: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TactileActionBtn(
            onTap: () => _sendNudge("You're doing great, keep going!"),
            icon: Icons.thumb_up_alt_outlined,
            label: "Encourage",
            color: tealAccent.withValues(alpha: 20),
            textColor: tealAccent,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0, left: 4),
      child: Text(text, style: const TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
    );
  }
}

class _TactileActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _TactileActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}