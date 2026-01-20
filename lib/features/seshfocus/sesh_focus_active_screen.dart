import 'package:flutter/material.dart';

class SeshFocusActiveScreen extends StatelessWidget {
  const SeshFocusActiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F142B),
      body: Center(
        child: Text(
          "SeshFocus Active",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
