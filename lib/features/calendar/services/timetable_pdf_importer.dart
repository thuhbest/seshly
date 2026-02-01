import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:seshly/services/sesh_ai_api.dart';

class TimetablePdfImporter {
  TimetablePdfImporter({SeshAiApi? api}) : _api = api ?? SeshAiApi();

  final SeshAiApi _api;

  Future<int> importForMonth(DateTime month) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }

    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      withReadStream: true,
    );

    if (res == null || res.files.isEmpty) return 0;
    final file = res.files.first;

    final bytes = await _readFileBytes(file);
    if (bytes == null) return 0;

    final url = await _uploadBytes(
      bytes,
      'users/${user.uid}/ai/calendar/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      'application/pdf',
    );
    if (url == null) return 0;

    final timezone = _resolveTimezone();
    final response = await _api.calendarImportTimetable(
      timetablePdfSignedUrl: url,
      timezone: timezone,
    );

    final created = response['eventsCreated'];
    if (created is int) return created;
    if (created is num) return created.toInt();
    return 0;
  }

  Future<String?> _uploadBytes(Uint8List bytes, String path, String contentType) async {
    final ref = FirebaseStorage.instance.ref().child(path);
    final metadata = SettableMetadata(contentType: contentType);
    final task = await ref.putData(bytes, metadata);
    return task.ref.getDownloadURL();
  }

  String _resolveTimezone() {
    final name = DateTime.now().timeZoneName;
    final offset = DateTime.now().timeZoneOffset;
    if (name == 'SAST' || offset == const Duration(hours: 2)) {
      return 'Africa/Johannesburg';
    }
    if (name.isEmpty) return 'UTC';
    if (name.toUpperCase().startsWith('UTC') || name.toUpperCase().startsWith('GMT')) {
      return 'UTC';
    }
    return name;
  }
}

Future<Uint8List?> _readFileBytes(PlatformFile file) async {
  if (file.bytes != null) return file.bytes;
  final stream = file.readStream;
  if (stream == null) return null;
  final chunks = <int>[];
  await for (final chunk in stream) {
    chunks.addAll(chunk);
  }
  return Uint8List.fromList(chunks);
}
