import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/calendar_event.dart';

class CalendarRepository {
  CalendarRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('User not signed in.');
    }
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _eventsCol =>
      _db.collection('users').doc(_uid).collection('calendarEvents');

  DocumentReference<Map<String, dynamic>> getTimetableDoc(String timetableId) =>
      _db.collection('users').doc(_uid).collection('timetables').doc(timetableId);

  Stream<List<CalendarEvent>> streamEventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day, 0, 0, 0);
    final end = start.add(const Duration(days: 1));
    return _eventsCol
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(start.toUtc()))
        .where('start', isLessThan: Timestamp.fromDate(end.toUtc()))
        .orderBy('start')
        .snapshots()
        .map((snap) => snap.docs.map(CalendarEvent.fromDoc).toList());
  }

  Stream<List<CalendarEvent>> streamEventsForMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1, 0, 0, 0);
    final end = DateTime(month.year, month.month + 1, 1, 0, 0, 0);
    return _eventsCol
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(start.toUtc()))
        .where('start', isLessThan: Timestamp.fromDate(end.toUtc()))
        .orderBy('start')
        .snapshots()
        .map((snap) => snap.docs.map(CalendarEvent.fromDoc).toList());
  }

  Stream<List<CalendarEvent>> streamUpcomingEvents({int daysAhead = 30}) {
    final now = DateTime.now();
    final end = now.add(Duration(days: daysAhead));
    return _eventsCol
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(now.toUtc()))
        .where('start', isLessThanOrEqualTo: Timestamp.fromDate(end.toUtc()))
        .orderBy('start')
        .snapshots()
        .map((snap) => snap.docs.map(CalendarEvent.fromDoc).toList());
  }

  Future<void> addEvent(CalendarEvent e) async {
    await _eventsCol.doc(e.id).set(e.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteEvent(String id) async {
    await _eventsCol.doc(id).delete();
  }

  Future<void> upsertTimetableMeta({
    required String timetableId,
    required String filename,
    required String sha1,
    required DateTime importedAt,
    required String rawTextPreview,
  }) async {
    await getTimetableDoc(timetableId).set({
      'filename': filename,
      'sha1': sha1,
      'importedAt': Timestamp.fromDate(importedAt.toUtc()),
      'rawTextPreview': rawTextPreview,
    }, SetOptions(merge: true));
  }

  Future<bool> timetableAlreadyImported(String timetableId) async {
    final doc = await getTimetableDoc(timetableId).get();
    return doc.exists;
  }
}
