import 'package:flutter/material.dart';

class SessionWrapView extends StatefulWidget {
  const SessionWrapView({super.key});

  @override
  State<SessionWrapView> createState() => _SessionWrapViewState();
}

class _SessionWrapViewState extends State<SessionWrapView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  String _selectedStyle = "Exam Focused";
  bool _includeHomework = true;
  bool _isGenerating = false;

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
                  child: Text("Sesh AI is compiling 14 board snapshots and 45min of audio.", 
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
                setState(() => _isGenerating = true);
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
    return GestureDetector(
      onTap: () => setState(() => _selectedStyle = label),
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