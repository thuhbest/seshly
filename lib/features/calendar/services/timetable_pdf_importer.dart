import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../data/calendar_repository.dart';
import '../models/calendar_event.dart';

Map<String, Object?> _extractAndParsePdf(Uint8List bytes) {
  final text = _extractText(bytes);
  final preview = text.length > 800 ? text.substring(0, 800) : text;
  final items = _parseWeeklyItemsToMaps(text);
  return {'preview': preview, 'items': items};
}
String _extractText(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final extractor = PdfTextExtractor(doc);
  final text = extractor.extractText();
  doc.dispose();
  return text;
}

List<Map<String, Object?>> _parseWeeklyItemsToMaps(String raw) {
  final cleaned = raw
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll('\u00A0', ' ')
      .trim();

  final weekdayMap = <String, int>{
    'mon': DateTime.monday,
    'monday': DateTime.monday,
    'tue': DateTime.tuesday,
    'tues': DateTime.tuesday,
    'tuesday': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'wednesday': DateTime.wednesday,
    'thu': DateTime.thursday,
    'thur': DateTime.thursday,
    'thurs': DateTime.thursday,
    'thursday': DateTime.thursday,
    'fri': DateTime.friday,
    'friday': DateTime.friday,
    'sat': DateTime.saturday,
    'saturday': DateTime.saturday,
    'sun': DateTime.sunday,
    'sunday': DateTime.sunday,
  };

  final timeRange = RegExp(
    r'(?:(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?\s*[--]\s*(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?)',
  );

  final lines = cleaned.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final items = <Map<String, Object?>>[];

  for (final line in lines) {
    final lower = line.toLowerCase();

    int? weekday;
    for (final entry in weekdayMap.entries) {
      if (lower.startsWith('${entry.key} ') || lower.contains(' ${entry.key} ')) {
        weekday = entry.value;
        break;
      }
    }
    if (weekday == null) continue;

    final m = timeRange.firstMatch(line);
    if (m == null) continue;

    final start = _parseTime(
      hour: int.parse(m.group(1)!),
      minute: int.parse(m.group(2)!),
      ampm: m.group(3),
    );
    final end = _parseTime(
      hour: int.parse(m.group(4)!),
      minute: int.parse(m.group(5)!),
      ampm: m.group(6),
    );

    final withoutTime = line.replaceRange(m.start, m.end, ' ').trim();

    final parts = withoutTime.split(' ');
    final trimmedParts = parts.where((p) {
      final pl = p.toLowerCase();
      return !weekdayMap.containsKey(pl);
    }).toList();

    final remainder = trimmedParts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (remainder.isEmpty) continue;

    final location = _extractLocation(remainder);
    final title = location == null ? remainder : remainder.replaceFirst(location, '').trim();
    final guessedType = _guessType(title);

    items.add({
      'weekday': weekday,
      'startHour': start.hour,
      'startMinute': start.minute,
      'endHour': end.hour,
      'endMinute': end.minute,
      'title': title.isEmpty ? remainder : title,
      'location': location ?? '',
      'type': guessedType,
    });
  }

  final uniq = <String, Map<String, Object?>>{};
  for (final it in items) {
    final weekday = it['weekday'] as int;
    final startHour = it['startHour'] as int;
    final startMinute = it['startMinute'] as int;
    final endHour = it['endHour'] as int;
    final endMinute = it['endMinute'] as int;
    final title = (it['title'] as String?) ?? '';
    final location = (it['location'] as String?) ?? '';
    final type = (it['type'] as String?) ?? '';
    final sig = _weeklySignature(weekday, startHour, startMinute, endHour, endMinute, title, location, type);
    uniq[sig] = it;
  }
  return uniq.values.toList();
}

_ClockTime _parseTime({required int hour, required int minute, String? ampm}) {
  int h = hour;
  final ap = (ampm ?? '').toLowerCase();

  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;

  return _ClockTime(h.clamp(0, 23), minute.clamp(0, 59));
}

String? _extractLocation(String s) {
  final patterns = [
    RegExp(r'\bRoom\b.*$', caseSensitive: false),
    RegExp(r'\bBuilding\b.*$', caseSensitive: false),
    RegExp(r'\bLibrary\b.*$', caseSensitive: false),
    RegExp(r'\bOnline\b.*$', caseSensitive: false),
    RegExp(r'\bZoom\b.*$', caseSensitive: false),
    RegExp(r'\bMS Teams\b.*$', caseSensitive: false),
    RegExp(r'\bVenue\b.*$', caseSensitive: false),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m != null) return s.substring(m.start).trim();
  }
  return null;
}

String _guessType(String title) {
  final t = title.toLowerCase();
  if (t.contains('exam') || t.contains('midterm') || t.contains('test')) return 'Exam';
  if (t.contains('lab') || t.contains('lecture') || t.contains('class') || t.contains('tutorial')) return 'Class';
  if (t.contains('assignment') || t.contains('due')) return 'Assignment';
  if (t.contains('deadline')) return 'Deadline';
  if (t.contains('study group') || t.contains('group')) return 'Study Group';
  if (t.contains('tutor') || t.contains('tutoring')) return 'Tutoring';
  if (t.contains('meeting') || t.contains('meet')) return 'Meeting';
  return 'Class';
}

String _weeklySignature(
  int weekday,
  int startHour,
  int startMinute,
  int endHour,
  int endMinute,
  String title,
  String location,
  String type,
) {
  return '${weekday}_${startHour}:${startMinute}_${endHour}:${endMinute}_${title.toLowerCase()}_${location.toLowerCase()}_${type.toLowerCase()}';
}

List<_WeeklyItem> _weeklyItemsFromMaps(List<dynamic>? rawItems) {
  if (rawItems == null) return const <_WeeklyItem>[];
  final items = <_WeeklyItem>[];
  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final weekday = raw['weekday'];
    final startHour = raw['startHour'];
    final startMinute = raw['startMinute'];
    final endHour = raw['endHour'];
    final endMinute = raw['endMinute'];
    final title = raw['title'];
    final location = raw['location'];
    final type = raw['type'];
    if (weekday is! int ||
        startHour is! int ||
        startMinute is! int ||
        endHour is! int ||
        endMinute is! int ||
        title is! String ||
        location is! String ||
        type is! String) {
      continue;
    }
    items.add(_WeeklyItem(
      weekday: weekday,
      start: _ClockTime(startHour, startMinute),
      end: _ClockTime(endHour, endMinute),
      title: title,
      location: location,
      type: type,
    ));
  }
  return items;
}

class TimetablePdfImporter {
  TimetablePdfImporter(this._repo);

  final CalendarRepository _repo;

  Future<int> importForMonth(DateTime month) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true, // web/desktop often gives bytes, mobile sometimes not
    );

    if (res == null || res.files.isEmpty) return 0;
    final file = res.files.first;

    Uint8List? bytes = file.bytes;

    // ✅ Correct fallback (mobile/desktop) when bytes is null:
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) return 0;

    final sha = sha1.convert(bytes).toString();
    final timetableId = sha;

    final exists = await _repo.timetableAlreadyImported(timetableId);
    if (exists) return 0;

    Map<String, Object?> parsedResult;
    try {
      parsedResult = await compute(_extractAndParsePdf, bytes);
    } catch (_) {
      final text = _extractText(bytes);
      final preview = text.length > 800 ? text.substring(0, 800) : text;
      parsedResult = {
        'preview': preview,
        'items': _parseWeeklyItemsToMaps(text),
      };
    }

    final preview = (parsedResult['preview'] as String?) ?? '';

    await _repo.upsertTimetableMeta(
      timetableId: timetableId,
      filename: file.name,
      sha1: sha,
      importedAt: DateTime.now(),
      rawTextPreview: preview,
    );

    final parsed = _weeklyItemsFromMaps(parsedResult['items'] as List<dynamic>?);
    if (parsed.isEmpty) return 0;

    final events = _expandToMonth(month, parsed, timetableId);

    for (final e in events) {
      await _repo.addEvent(e);
    }

    return events.length;
  }

  List<CalendarEvent> _expandToMonth(DateTime month, List<_WeeklyItem> weekly, String timetableId) {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final startNextMonth = DateTime(month.year, month.month + 1, 1);

    final events = <CalendarEvent>[];

    for (final w in weekly) {
      DateTime d = startOfMonth;
      while (d.isBefore(startNextMonth) && d.weekday != w.weekday) {
        d = d.add(const Duration(days: 1));
      }

      while (d.isBefore(startNextMonth)) {
        final start = DateTime(d.year, d.month, d.day, w.start.hour, w.start.minute);
        final end = DateTime(d.year, d.month, d.day, w.end.hour, w.end.minute);

        final colorHex = EventTypePalette.colorHexForType(w.type);

        final idSeed = '${timetableId}_${d.toIso8601String()}_${w.signature}';
        final id = sha1.convert(utf8.encode(idSeed)).toString();

        events.add(CalendarEvent(
          id: id,
          title: w.title,
          start: start,
          end: end.isAfter(start) ? end : start.add(const Duration(hours: 1)),
          location: w.location,
          type: w.type,
          colorHex: colorHex,
          source: 'pdf',
          timetableId: timetableId,
          createdAt: DateTime.now(),
        ));

        d = d.add(const Duration(days: 7));
      }
    }

    return events;
  }

}

class _ClockTime {
  final int hour;
  final int minute;
  const _ClockTime(this.hour, this.minute);
}

class _WeeklyItem {
  final int weekday;
  final _ClockTime start;
  final _ClockTime end;
  final String title;
  final String location;
  final String type;

  _WeeklyItem({
    required this.weekday,
    required this.start,
    required this.end,
    required this.title,
    required this.location,
    required this.type,
  });

  String get signature =>
      '${weekday}_${start.hour}:${start.minute}_${end.hour}:${end.minute}_${title.toLowerCase()}_${location.toLowerCase()}_${type.toLowerCase()}';
}
