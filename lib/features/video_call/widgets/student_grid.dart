import 'package:flutter/material.dart';
import 'student_tile.dart';

class StudentGrid extends StatelessWidget {
  const StudentGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> students = [
      {'name': 'Luko', 'status': 'Working', 'progress': 0.7},
      {'name': 'Thuhbest', 'status': 'Stuck', 'progress': 0.3},
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: students.length,
      itemBuilder: (context, index) {
        return StudentTile(
          name: students[index]['name'],
          status: students[index]['status'],
          progress: students[index]['progress'],
        );
      },
    );
  }
}