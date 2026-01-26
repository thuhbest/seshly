import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SeshFocusService {
  static const _channel = MethodChannel('seshly/seshfocus');
  static bool get _supportsPinning =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start(int minutes) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'seshFocusActive': true,
      'seshFocusEndsAt':
          Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes))),
    });

    if (_supportsPinning) {
      await _channel.invokeMethod('startPinning', {
        'minutes': minutes,
      });
    }
  }

  static Future<void> stop() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    if (_supportsPinning) {
      await _channel.invokeMethod('stopPinning');
    }

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'seshFocusActive': false,
      'seshFocusEndsAt': null,
    });
  }
}
