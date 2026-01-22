import 'package:flutter/material.dart';
import '../models/session_mode.dart';
import '../widgets/mode_switch_pill.dart';
import '../widgets/student_grid.dart';
import '../widgets/shared_board.dart';
import '../widgets/right_rail.dart';
import '../widgets/give_task_modal.dart';

class ParallelPracticeView extends StatefulWidget {
  const ParallelPracticeView({super.key});

  @override
  State<ParallelPracticeView> createState() => _ParallelPracticeViewState();
}

class _ParallelPracticeViewState extends State<ParallelPracticeView> {
  SessionMode _currentMode = SessionMode.teach;
  final bool _isRailExpanded = true;

  final Color backgroundColor = const Color(0xFF0F142B);
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);

  @override
  Widget build(BuildContext context) {
    final bool isWide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildMainCanvas()),
                if (_isRailExpanded && isWide) const RightRail(),
              ],
            ),
          ),
          _buildBottomBar(isWide),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final bool isWide = MediaQuery.of(context).size.width >= 900;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: cardColor),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios,
                      color: Colors.white, size: 18)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    "Calculus: Limits",
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ModeSwitchPill(
                currentMode: _currentMode,
                onChanged: (mode) => setState(() => _currentMode = mode),
              ),
            ),
          ),
          if (isWide)
            Row(
              children: [
                _buildConnectionIndicator(),
                const SizedBox(width: 15),
                const Icon(Icons.settings_outlined, color: Colors.white70),
              ],
            )
          else
            _buildConnectionIndicator(),
        ],
      ),
    );
  }

  Widget _buildMainCanvas() {
    switch (_currentMode) {
      case SessionMode.teach:
        return const SharedBoard();
      case SessionMode.practice:
        return const StudentGrid();
      case SessionMode.review:
        return const Center(
            child: Text("Review Mode Active",
                style: TextStyle(color: Colors.white54)));
    }
  }

  Widget _buildBottomBar(bool isWide) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(color: cardColor),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.mic_none, color: Colors.white),
                SizedBox(width: 20),
                Icon(Icons.videocam_outlined, color: Colors.white),
              ],
            ),
            const SizedBox(width: 20),
            if (isWide) _buildBoardToolbar(),
            const SizedBox(width: 20),
            Row(
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C09E)),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const GiveTaskModal(),
                    );
                  },
                  child: const Text("Give Task",
                      style: TextStyle(color: Color(0xFF0F142B))),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: _showEndSessionDialog,
                  child: const Text("End Session"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: tealAccent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        const Text("Live",
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildBoardToolbar() {
    return Row(
      children: [
        IconButton(
            icon: const Icon(Icons.edit, color: Colors.white70),
            onPressed: () {}),
        IconButton(
            icon: const Icon(Icons.auto_fix_normal, color: Colors.white70),
            onPressed: () {}),
        IconButton(
            icon: const Icon(Icons.undo, color: Colors.white70),
            onPressed: () {}),
      ],
    );
  }

  void _showEndSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text("End session?",
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("End",
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }
}
