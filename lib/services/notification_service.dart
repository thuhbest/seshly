import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> initForUser(User user) async {
    final bool pushEnabled = await _isPushEnabled(user.uid);
    if (!pushEnabled) return;

    await _messaging.requestPermission();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(user.uid, token);
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      if (await _isPushEnabled(user.uid)) {
        await _saveToken(user.uid, newToken);
      }
    });
  }

  Future<void> disableForUser(User user) async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('fcmTokens')
          .doc(token)
          .delete();
    }
    await _messaging.deleteToken();
  }

  Future<void> _saveToken(String userId, String token) async {
    final tokenRef = _db
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(token);
    await tokenRef.set({
      'token': token,
      'platform': _platformLabel(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> _isPushEnabled(String userId) async {
    final userDoc = await _db.collection('users').doc(userId).get();
    final data = userDoc.data() ?? {};
    final prefs = data['notificationPrefs'] as Map<String, dynamic>? ?? {};
    return prefs['push'] != false;
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
