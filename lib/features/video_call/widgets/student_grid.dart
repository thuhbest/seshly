import 'package:flutter/material.dart';

import 'student_tile.dart';

class StudentGrid extends StatelessWidget {
  const StudentGrid({
    super.key,
    required this.students,
    this.onSoftSpotlight,
    this.onHardSpotlight,
    this.onBroadcast,
  });

  final List<ClassroomStudentTileData> students;
  final void Function(ClassroomStudentTileData student)? onSoftSpotlight;
  final void Function(ClassroomStudentTileData student)? onHardSpotlight;
  final void Function(ClassroomStudentTileData student)? onBroadcast;

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return Center(
        child: Text(
          'Students will appear here once the classroom is live.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.46)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        childAspectRatio: 1.08,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: students.length,
      itemBuilder: (context, index) {
        final student = students[index];
        return StudentTile(
          data: student,
          onSoftSpotlight:
              onSoftSpotlight == null ? null : () => onSoftSpotlight!(student),
          onHardSpotlight:
              onHardSpotlight == null ? null : () => onHardSpotlight!(student),
          onBroadcast:
              onBroadcast == null ? null : () => onBroadcast!(student),
        );
      },
    );
  }
}
