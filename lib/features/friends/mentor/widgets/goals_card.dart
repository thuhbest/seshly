import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class GoalsCard extends StatelessWidget {
  final List<Map<String, dynamic>> goals;
  final VoidCallback onAddGoal;
  final void Function(String goalId, int progress, int target) onUpdateGoal;

  const GoalsCard({
    super.key,
    required this.goals,
    required this.onAddGoal,
    required this.onUpdateGoal,
  });

  @override
  Widget build(BuildContext context) {
    final displayGoals = goals.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.track_changes, color: Color(0xFF00C09E), size: 20),
                  SizedBox(width: 8),
                  Text("Monthly Goals", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              PressableScale(
                onTap: onAddGoal,
                borderRadius: BorderRadius.circular(12),
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Text("+ Add Goal", style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (displayGoals.isEmpty)
            const Text(
              "Set a goal tied to your faculty benchmarks or milestones.",
              style: TextStyle(color: Color(0x61FFFFFF), fontSize: 12),
            )
          else
            ...displayGoals.map((goal) => _GoalItem(
                  goal: goal,
                  onUpdate: (goalId, progress, target) => onUpdateGoal(goalId, progress, target),
                )),
        ],
      ),
    );
  }
}

class _GoalItem extends StatelessWidget {
  final Map<String, dynamic> goal;
  final void Function(String goalId, int progress, int target) onUpdate;

  const _GoalItem({required this.goal, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final goalId = goal['id']?.toString() ?? '';
    final title = (goal['title'] ?? 'Goal').toString();
    final type = (goal['type'] ?? 'Personal').toString();
    final progress = (goal['progress'] as num?)?.toInt() ?? 0;
    final target = (goal['target'] as num?)?.toInt() ?? 100;
    final dueLabel = (goal['dueLabel'] ?? '').toString();
    final ratio = target == 0 ? 0.0 : (progress / target).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
              Text("${(ratio * 100).round()}%", style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(type, style: const TextStyle(color: Color(0x61FFFFFF), fontSize: 11)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: const Color(0x1AFFFFFF),
              color: const Color(0xFF00C09E),
              minHeight: 6,
            ),
          ),
          if (dueLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text("Due: $dueLabel", style: const TextStyle(color: Color(0x61FFFFFF), fontSize: 11)),
          ],
          if (goalId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: PressableScale(
                onTap: () => onUpdate(goalId, progress, target),
                borderRadius: BorderRadius.circular(10),
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Text("Update", style: TextStyle(color: Colors.white70, fontSize: 12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
