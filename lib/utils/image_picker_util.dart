import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ImagePickResult {
  final Uint8List bytes;
  final String? name;

  const ImagePickResult({required this.bytes, this.name});
}

bool _supportsImagePicker() {
  return kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

bool supportsCameraPicker() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
}

Future<Uint8List?> _readPlatformFileBytes(PlatformFile file) async {
  if (file.bytes != null) return file.bytes;
  final stream = file.readStream;
  if (stream == null) return null;
  final chunks = <int>[];
  await for (final chunk in stream) {
    chunks.addAll(chunk);
  }
  return Uint8List.fromList(chunks);
}

Future<ImagePickResult?> pickImageBytes({
  required ImageSource source,
  int imageQuality = 80,
}) async {
  if (source == ImageSource.camera && !supportsCameraPicker()) {
    return null;
  }

  if (_supportsImagePicker()) {
    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: imageQuality,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return ImagePickResult(bytes: bytes, name: picked.name.isNotEmpty ? picked.name : null);
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
    withReadStream: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final bytes = await _readPlatformFileBytes(file);
  if (bytes == null) return null;
  return ImagePickResult(bytes: bytes, name: file.name);
}
