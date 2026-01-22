import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/features/home/view/main_wrapper.dart';
import 'package:seshly/services/sesh_focus_service.dart';

class SeshFocusActiveScreen extends StatefulWidget {
  const SeshFocusActiveScreen({super.key});

  @override
  State<SeshFocusActiveScreen> createState() => _SeshFocusActiveScreenState();
}

class _SeshFocusActiveScreenState extends State<SeshFocusActiveScreen> {
  Timer? _ticker;
  bool _isEnding = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _endSession() async {
    try {
      await SeshFocusService.stop();
    } catch (_) {
      // Ignore stop failures; we'll still return to the app shell.
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainWrapper()),
      (_) => false,
    );
  }

  void _scheduleEndSession() {
    if (_isEnding) return;
    _isEnding = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: unawaited_futures
      _endSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Text("SeshFocus Active", style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: tealAccent));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final bool isActive = data['seshFocusActive'] == true;
          final Timestamp? endsAt = data['seshFocusEndsAt'] as Timestamp?;

          if (!isActive || endsAt == null) {
            _scheduleEndSession();
            return const Center(child: CircularProgressIndicator(color: tealAccent));
          }

          final DateTime endTime = endsAt.toDate();
          final Duration remaining = endTime.difference(DateTime.now());
          if (remaining.isNegative) {
            _scheduleEndSession();
            return const Center(child: CircularProgressIndicator(color: tealAccent));
          }

          final int totalSeconds = remaining.inSeconds;
          final int minutes = totalSeconds ~/ 60;
          final int seconds = totalSeconds % 60;
          final String countdown = "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: tealAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_rounded, color: tealAccent, size: 32),
                ),
                const SizedBox(height: 18),
                const Text(
                  "SeshFocus Active",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Time left $countdown",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                ),
                const SizedBox(height: 24),
                Text(
                  "Stay locked in. You'll return automatically when the timer ends.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, height: 1.4),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
