import 'package:flutter/material.dart';

class SharedBoard extends StatelessWidget {
  const SharedBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: Icon(Icons.edit_note, size: 100, color: Colors.black12)),
    );
  }
}