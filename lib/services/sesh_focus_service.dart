import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SeshFocusService {
  static const _channel = MethodChannel('seshly/seshfocus');

  static Future<void> start(int minutes) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'seshFocusActive': true,
      'seshFocusEndsAt':
          Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes))),
    });

    if (Platform.isAndroid) {
      await _channel.invokeMethod('startPinning', {
        'minutes': minutes,
      });
    }
  }

  static Future<void> stop() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    if (Platform.isAndroid) {
      await _channel.invokeMethod('stopPinning');
    }

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'seshFocusActive': false,
      'seshFocusEndsAt': null,
    });
  }
}
