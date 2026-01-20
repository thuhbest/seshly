import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sesh_focus_service.dart';

class SeshFocusUnlock {
  static Future<bool> unlockEarly() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();

    int passes = snap['focusEmergencyPasses'] ?? 2;
    int seshMinutes = snap['seshMinutes'] ?? 0;

    // Monthly reset
    final now = DateTime.now();
    final lastReset = (snap['lastFocusReset'] as Timestamp?)?.toDate();

    if (lastReset == null ||
        lastReset.month != now.month ||
        lastReset.year != now.year) {
      passes = 2;
      await ref.update({
        'focusEmergencyPasses': 2,
        'lastFocusReset': FieldValue.serverTimestamp(),
      });
    }

    // Free pass
    if (passes > 0) {
      await ref.update({
        'focusEmergencyPasses': passes - 1,
        'xp': FieldValue.increment(-50),
      });

      await SeshFocusService.stop();
      return true;
    }

    // Paid unlock
    if (seshMinutes >= 10) {
      await ref.update({
        'seshMinutes': FieldValue.increment(-10),
        'xp': FieldValue.increment(-50),
      });

      await SeshFocusService.stop();
      return true;
    }

    return false; // Block unlock
  }
}
