import 'package:flutter/material.dart';

class StudentTile extends StatelessWidget {
  final String name;
  final String status;
  final double progress;

  const StudentTile({
    super.key,
    required this.name,
    required this.status,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final Color tealAccent = const Color(0xFF00C09E);
    final Color cardColor = const Color(0xFF1E243A);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status == "Stuck" ? Colors.redAccent : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 12, backgroundColor: tealAccent),
            title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 12)),
            trailing: _buildStatusChip(status),
          ),
          const Expanded(
            child: Center(child: Icon(Icons.gesture, color: Colors.white24, size: 40)),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              color: tealAccent,
              minHeight: 4,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = (status == "Stuck") ? Colors.redAccent : const Color(0xFF00C09E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}