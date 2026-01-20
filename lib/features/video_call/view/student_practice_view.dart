import 'package:flutter/material.dart';
import '../models/session_mode.dart';

class StudentPracticeView extends StatefulWidget {
  const StudentPracticeView({super.key});

  @override
  State<StudentPracticeView> createState() => _StudentPracticeViewState();
}

class _StudentPracticeViewState extends State<StudentPracticeView> {
  // Logic: In a real app, this mode is pushed via WebSocket/Firebase from the Tutor
  SessionMode _currentMode = SessionMode.teach;
  
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildStudentHeader(),
              if (_currentMode == SessionMode.practice) _buildTaskBanner(),
              Expanded(
                child: _currentMode == SessionMode.teach 
                    ? _buildSharedView() 
                    : _buildPrivateWorkArea(),
              ),
              _buildStudentBottomBar(),
            ],
          ),
          if (_currentMode == SessionMode.practice) _buildSeshAIFloatingButton(),
        ],
      ),
    );
  }

  Widget _buildStudentHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 15),
      color: cardColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Calculus Group Session", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(_currentMode == SessionMode.teach ? "Watching Tutor" : "Private Practice", 
                style: TextStyle(color: tealAccent, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          const CircleAvatar(radius: 15, backgroundColor: Colors.white10, child: Icon(Icons.person, size: 18, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildTaskBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: tealAccent.withValues(alpha: 30),
      child: Row(
        children: [
          Icon(Icons.assignment_turned_in_rounded, color: tealAccent, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "TASK: Calculate the limit as x approaches 0 for sin(x)/x. Show all steps.",
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const Text("04:52", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildSharedView() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: const Center(child: Text("Tutor is presenting...", style: TextStyle(color: Colors.black26))),
    );
  }

  Widget _buildPrivateWorkArea() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tealAccent.withValues(alpha: 100), width: 2),
      ),
      child: Stack(
        children: [
          const Center(child: Icon(Icons.edit_note_rounded, size: 60, color: Colors.black12)),
          Positioned(
            bottom: 15,
            left: 15,
            child: Text("PRIVATE BOARD", style: TextStyle(color: Colors.black.withValues(alpha: 50), fontWeight: FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(color: cardColor, border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 10)))),
      child: Row(
        children: [
          const Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 28),
          const SizedBox(width: 25),
          const Icon(Icons.videocam_rounded, color: Colors.white, size: 28),
          const Spacer(),
          if (_currentMode == SessionMode.practice)
            ElevatedButton(
              onPressed: () {
                // Logic: Submit board to Tutor
                setState(() => _currentMode = SessionMode.teach);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text("SUBMIT", style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold)),
            ),
          if (_currentMode == SessionMode.teach)
             const Text("Waiting for task...", style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSeshAIFloatingButton() {
    return Positioned(
      right: 30,
      bottom: 100,
      child: GestureDetector(
        onTap: () {
           // Logic: Open Sesh AI rate-limited hint modal
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            shape: BoxShape.circle,
            border: Border.all(color: tealAccent, width: 2),
            boxShadow: [BoxShadow(color: tealAccent.withValues(alpha: 100), blurRadius: 15)],
          ),
          child: Icon(Icons.auto_awesome, color: tealAccent, size: 30),
        ),
      ),
    );
  }
}