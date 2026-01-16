import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SeshFocusService {
  static const MethodChannel _channel =
      MethodChannel('seshly/seshfocus');

  static Timer? _timer;

  static Future<void> start({required int durationMinutes}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final endTime =
        DateTime.now().add(Duration(minutes: durationMinutes));

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'seshFocusActive': true,
      'seshFocusEndsAt': endTime,
    });

    if (Platform.isAndroid) {
      await _channel.invokeMethod('startLock', {
        'duration': durationMinutes,
      });
    }

    _timer = Timer(Duration(minutes: durationMinutes), () {
      stop(force: false);
    });
  }

  static Future<void> stop({required bool force}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (Platform.isAndroid) {
      await _channel.invokeMethod('stopLock');
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'seshFocusActive': false,
      'seshFocusEndsAt': null,
    });

    _timer?.cancel();
    _timer = null;
  }

  /// Emergency exit: consumes pass + XP penalty
  static Future<bool> emergencyExit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};

    final now = DateTime.now();
    final lastReset =
        (data['lastEmergencyReset'] as Timestamp?)?.toDate();

    int passes = data['emergencyPasses'] ?? 2;

    if (lastReset == null ||
        lastReset.month != now.month ||
        lastReset.year != now.year) {
      passes = 2;
      await ref.update({
        'emergencyPasses': 2,
        'lastEmergencyReset': FieldValue.serverTimestamp(),
      });
    }

    if (passes <= 0) return false;

    await ref.update({
      'emergencyPasses': passes - 1,
      'xp': FieldValue.increment(-50), // XP PENALTY
    });

    await stop(force: true);
    return true;
  }

  /// Enforce re-entry on iOS
  static void attachLifecycleGuard(BuildContext context) {
    WidgetsBinding.instance.addObserver(
      _FocusLifecycleObserver(context),
    );
  }
}

class _FocusLifecycleObserver extends WidgetsBindingObserver {
  final BuildContext context;
  _FocusLifecycleObserver(this.context);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final active = snap.data()?['seshFocusActive'] == true;

      if (active && Platform.isIOS) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/seshFocusActive',
          (_) => false,
        );
      }
    }
  }
}
