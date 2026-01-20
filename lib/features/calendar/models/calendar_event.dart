import 'package:cloud_firestore/cloud_firestore.dart';

class CalendarEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String type; // Tutoring, Class, Exam, Deadline, Meeting, Assignment, Study Group, Reminder, etc.
  final int colorHex; // 0xAARRGGBB
  final String source; // manual | pdf
  final String? timetableId; // set when imported from PDF
  final DateTime createdAt;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.type,
    required this.colorHex,
    required this.source,
    required this.createdAt,
    this.timetableId,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'start': Timestamp.fromDate(start.toUtc()),
      'end': Timestamp.fromDate(end.toUtc()),
      'location': location,
      'type': type,
      'colorHex': colorHex,
      'source': source,
      'timetableId': timetableId,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    };
  }

  static CalendarEvent fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final type = (data['type'] ?? 'Event') as String;
    final rawColorHex = data['colorHex'];
    final storedHex = rawColorHex is int ? rawColorHex : null;
    final colorHex = EventTypePalette.resolveColorHex(type: type, storedHex: storedHex);
    return CalendarEvent(
      id: doc.id,
      title: (data['title'] ?? '') as String,
      start: ((data['start'] as Timestamp?)?.toDate() ?? DateTime.now()).toLocal(),
      end: ((data['end'] as Timestamp?)?.toDate() ?? DateTime.now()).toLocal(),
      location: (data['location'] ?? '') as String,
      type: type,
      colorHex: colorHex,
      source: (data['source'] ?? 'manual') as String,
      timetableId: data['timetableId'] as String?,
      createdAt: ((data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now()).toLocal(),
    );
  }
}

class EventTypePalette {
  // Muted Seshly palette for calendar event accents.
  static const int _teal = 0xFF00C09E;
  static const int _tealLight = 0xFF3BCDB3;
  static const int _aqua = 0xFF4CC7D6;
  static const int _mint = 0xFF6FD2A9;
  static const int _blue = 0xFF6F8FE4;
  static const int _amber = 0xFFCEAC63;
  static const int _coral = 0xFFDE7272;

  static const Set<int> _legacyPalette = {
    0xFFFF3B30,
    0xFF0A84FF,
    0xFFFFCC00,
    0xFF34C759,
    0xFFAF52DE,
    0xFF00C09E,
  };

  static int colorHexForType(String type) {
    final t = type.trim().toLowerCase();
    if (t == 'exam') return _coral;
    if (t == 'class') return _aqua;
    if (t == 'assignment') return _amber;
    if (t == 'deadline') return _amber;
    if (t == 'study group') return _mint;
    if (t == 'tutoring') return _teal;
    if (t == 'meeting' || t == 'meetings') return _blue;
    if (t == 'reminder') return _tealLight;
    return _teal;
  }

  static int resolveColorHex({required String type, int? storedHex}) {
    if (storedHex == null) return colorHexForType(type);
    if (_legacyPalette.contains(storedHex)) return colorHexForType(type);
    return storedHex;
  }
}
