import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class ReviewComparisonTool extends StatefulWidget {
  const ReviewComparisonTool({super.key});

  @override
  State<ReviewComparisonTool> createState() => _ReviewComparisonToolState();
}

class _ReviewComparisonToolState extends State<ReviewComparisonTool> {
  // Logic: Store IDs of students currently being compared
  final List<String> _selectedStudentIds = [];
  
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  // Dummy data for student status in review
  final List<Map<String, dynamic>> _students = [
    {'id': '1', 'name': 'Luko', 'status': 'Done', 'tag': 'Good Method'},
    {'id': '2', 'name': 'Thuhbest', 'status': 'Stuck', 'tag': 'Algebra Gap'},
    {'id': '3', 'name': 'Sarah', 'status': 'Done', 'tag': 'Exemplar'},
    {'id': '4', 'name': 'Mike', 'status': 'Done', 'tag': 'Calculation Slip'},
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // --- LEFT: Student Selection List ---
        _buildStudentSidebar(),
        
        // --- CENTER: Comparison Workspace ---
        Expanded(
          child: _buildComparisonWorkspace(),
        ),
      ],
    );
  }

  Widget _buildStudentSidebar() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 128),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("Diagnostics", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final student = _students[index];
                final isSelected = _selectedStudentIds.contains(student['id']);
                
                return ListTile(
                  onTap: () => _toggleStudentSelection(student['id']),
                  selected: isSelected,
                  selectedTileColor: tealAccent.withValues(alpha: 25),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: student['status'] == 'Stuck' ? Colors.redAccent : tealAccent,
                    child: Text(student['name'][0], style: const TextStyle(fontSize: 10, color: Colors.black)),
                  ),
                  title: Text(student['name'], style: const TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: Text(student['tag'], style: TextStyle(color: tealAccent.withValues(alpha: 150), fontSize: 11)),
                  trailing: isSelected ? Icon(Icons.check_circle, color: tealAccent, size: 18) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonWorkspace() {
    if (_selectedStudentIds.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.compare_arrows_rounded, color: Colors.white.withValues(alpha: 25), size: 64),
            const SizedBox(height: 16),
            const Text("Select students to compare boards side-by-side", style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Workspace Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Comparing ${_selectedStudentIds.length} Boards", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => setState(() => _selectedStudentIds.clear()),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text("Clear"),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Comparison Grid
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _selectedStudentIds.length == 1 ? 1 : 2,
                childAspectRatio: 1.4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: _selectedStudentIds.length,
              itemBuilder: (context, index) {
                final student = _students.firstWhere((s) => s['id'] == _selectedStudentIds[index]);
                return _buildComparisonTile(student);
              },
            ),
          ),
          _buildReviewActions(),
        ],
      ),
    );
  }

  Widget _buildComparisonTile(Map<String, dynamic> student) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, // Board background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tealAccent.withValues(alpha: 50), width: 2),
      ),
      child: Stack(
        children: [
          const Center(child: Icon(Icons.gesture, color: Colors.black12, size: 48)),
          // Student Label Overlay
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(8)),
              child: Text(student['name'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          // Action buttons on board
          Positioned(
            bottom: 12,
            right: 12,
            child: Row(
              children: [
                _miniIconButton(Icons.comment_outlined, () {}),
                const SizedBox(width: 8),
                _miniIconButton(Icons.star_outline_rounded, () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewActions() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _diagnosticAction(Icons.record_voice_over_rounded, "Explain to Group", tealAccent),
          const SizedBox(width: 16),
          _diagnosticAction(Icons.send_rounded, "Send Correction", Colors.white70),
          const SizedBox(width: 16),
          _diagnosticAction(Icons.bookmark_added_rounded, "Mark as Exemplar", Colors.amberAccent),
        ],
      ),
    );
  }

  Widget _miniIconButton(IconData icon, VoidCallback onTap) {
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      pressedScale: 0.9,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: cardColor.withValues(alpha: 200), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white70, size: 14),
      ),
    );
  }

  Widget _diagnosticAction(IconData icon, String label, Color color) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 50)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {},
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  void _toggleStudentSelection(String id) {
    setState(() {
      if (_selectedStudentIds.contains(id)) {
        _selectedStudentIds.remove(id);
      } else {
        if (_selectedStudentIds.length < 3) {
          _selectedStudentIds.add(id);
        }
      }
    });
  }
}
