import 'package:flutter/material.dart';

class ClassroomStudentTileData {
  const ClassroomStudentTileData({
    required this.studentId,
    required this.name,
    required this.statusLabel,
    required this.progress,
    required this.focused,
    required this.spotlighted,
    required this.paused,
    required this.deEmphasized,
    required this.interventionLabel,
    this.boardId,
    this.previewLabel,
  });

  final String studentId;
  final String name;
  final String statusLabel;
  final double progress;
  final bool focused;
  final bool spotlighted;
  final bool paused;
  final bool deEmphasized;
  final String interventionLabel;
  final String? boardId;
  final String? previewLabel;
}

class StudentTile extends StatelessWidget {
  const StudentTile({
    super.key,
    required this.data,
    this.onSoftSpotlight,
    this.onHardSpotlight,
    this.onBroadcast,
  });

  final ClassroomStudentTileData data;
  final VoidCallback? onSoftSpotlight;
  final VoidCallback? onHardSpotlight;
  final VoidCallback? onBroadcast;

  @override
  Widget build(BuildContext context) {
    const tealAccent = Color(0xFF00C09E);
    const cardColor = Color(0xFF1E243A);
    final borderColor = data.spotlighted
        ? const Color(0xFFFFD166)
        : data.focused
            ? tealAccent
            : data.statusLabel == 'Stuck'
                ? Colors.redAccent
                : Colors.white.withValues(alpha: 0.10);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: data.deEmphasized ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: data.focused ? 1.4 : 1),
          boxShadow: data.spotlighted
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD166).withValues(alpha: 0.18),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: data.spotlighted
                        ? const Color(0xFFFFD166).withValues(alpha: 0.24)
                        : tealAccent.withValues(alpha: 0.22),
                    child: Text(
                      data.name.isEmpty ? '?' : data.name.characters.first.toUpperCase(),
                      style: TextStyle(
                        color: data.spotlighted ? const Color(0xFFFFD166) : tealAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          data.interventionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.50),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusChip(data.statusLabel),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F142B).withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            data.paused ? Icons.pause_circle_filled_rounded : Icons.draw_rounded,
                            color: data.paused ? Colors.orangeAccent : Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              data.previewLabel ?? 'Board live',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (data.boardId != null)
                        Text(
                          'Board ${data.boardId}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.36),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: data.progress.clamp(0, 1),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                color: data.spotlighted ? const Color(0xFFFFD166) : tealAccent,
                minHeight: 5,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _quickAction(
                      label: 'Soft',
                      icon: Icons.center_focus_weak_rounded,
                      enabled: onSoftSpotlight != null,
                      onTap: onSoftSpotlight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quickAction(
                      label: 'Jump In',
                      icon: Icons.center_focus_strong_rounded,
                      enabled: onHardSpotlight != null,
                      onTap: onHardSpotlight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quickAction(
                      label: 'Show',
                      icon: Icons.present_to_all_rounded,
                      enabled: onBroadcast != null,
                      onTap: onBroadcast,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final normalized = status.toLowerCase();
    final color = normalized.contains('spotlight')
        ? const Color(0xFFFFD166)
        : normalized.contains('stuck') || normalized.contains('paused')
            ? Colors.orangeAccent
            : const Color(0xFF00C09E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _quickAction({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final color = enabled ? Colors.white70 : Colors.white24;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.05 : 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: enabled ? 0.10 : 0.03)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
