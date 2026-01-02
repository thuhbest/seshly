import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ADD THIS MISSING SIGN IN METHOD
  Future<UserCredential> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException {
      // Re-throw the exception so it can be caught by the controller
      rethrow;
    } catch (e) {
      throw Exception('An unexpected error occurred: ${e.toString()}');
    }
  }

  // KEEP ALL YOUR EXISTING METHODS BELOW - DON'T CHANGE THEM
  Future<UserCredential?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String studentNumber,
    required String university,
    required String levelOfStudy,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = result.user;
      if (user != null) {
        await user.sendEmailVerification();
        final year = _convertLevelToYear(levelOfStudy);
        
        await _db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'fullName': fullName,
          'fullNameLowercase': fullName.toLowerCase(), 
          'studentNumber': studentNumber,
          // 🔥 Added for case-insensitive search by ID
          'studentNumberLowercase': studentNumber.toLowerCase(),
          'university': university,
          'levelOfStudy': levelOfStudy,
          'email': email,
          'emailVerified': false,
          'isDisabled': false,
          'createdAt': FieldValue.serverTimestamp(),
          'seshMinutes': 0,
          'streak': 0,
          'year': year,
          'major': '', 
          'id': studentNumber,
        });
      }
      return result;
    } on FirebaseAuthException {
      rethrow; 
    } catch (e) {
      throw Exception('An unexpected error occurred: ${e.toString()}');
    }
  }

  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? studentNumber, // Added to allow updating ID
    String? major,
    String? year,
    String? levelOfStudy,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      
      if (fullName != null) {
        updates['fullName'] = fullName;
        updates['fullNameLowercase'] = fullName.toLowerCase(); 
      }
      if (studentNumber != null) {
        updates['studentNumber'] = studentNumber;
        // 🔥 Keep searchable field in sync
        updates['studentNumberLowercase'] = studentNumber.toLowerCase();
      }
      if (major != null) updates['major'] = major;
      if (year != null) updates['year'] = year;
      if (levelOfStudy != null) {
        updates['levelOfStudy'] = levelOfStudy;
        updates['year'] = _convertLevelToYear(levelOfStudy);
      }
      
      if (updates.isNotEmpty) {
        await _db.collection('users').doc(userId).update(updates);
      }
    } catch (e) {
      rethrow;
    }
  }

  // KEEP YOUR convertLevelToYear METHOD
  String _convertLevelToYear(String levelOfStudy) {
    switch (levelOfStudy.toLowerCase()) {
      case 'first year':
      case '1st year':
        return '1st Year';
      case 'second year':
      case '2nd year':
        return '2nd Year';
      case 'third year':
      case '3rd year':
        return '3rd Year';
      case 'fourth year':
      case '4th year':
        return '4th Year';
      case 'postgraduate':
      case 'postgrad':
        return 'Postgrad';
      default:
        return levelOfStudy;
    }
  }

  // 🔥 UPDATED MIGRATION HELPER
 // 🔥 UPDATED MIGRATION HELPER - THIS IS CRITICAL
  Future<void> addLowerCaseFieldsToExistingUsers() async {
    try {
      final users = await _db.collection('users').get();
      WriteBatch batch = _db.batch();
      int count = 0;
      int totalUpdated = 0;

      for (final user in users.docs) {
        final data = user.data();
        final fullName = data['fullName'] as String?;
        final studentNumber = data['studentNumber'] as String?;
        Map<String, dynamic> updates = {};

        if (fullName != null && !data.containsKey('fullNameLowercase')) {
          updates['fullNameLowercase'] = fullName.toLowerCase();
        }
        if (studentNumber != null && !data.containsKey('studentNumberLowercase')) {
          updates['studentNumberLowercase'] = studentNumber.toLowerCase();
        }

        if (updates.isNotEmpty) {
          batch.update(user.reference, updates);
          count++;
          totalUpdated++;
        }

        // Firestore batch limit is 500 operations
        if (count >= 490) {
          await batch.commit();
          batch = _db.batch();
          count = 0;
          // ignore: avoid_print
          print('✅ Batch committed, updated $totalUpdated users so far...');
        }
      }
      
      if (count > 0) {
        await batch.commit();
      }
      
      // ignore: avoid_print
      print('🎉 MIGRATION COMPLETE: $totalUpdated users updated.');
      
    } catch (e) {
      // ignore: avoid_print
      print('❌ Migration error: $e');
      rethrow; // Important: rethrow so you can see the error
    }
  }
}