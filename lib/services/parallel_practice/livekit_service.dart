import 'dart:async';

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

class LiveKitService {
  LiveKitService({required FirebaseAuth auth, required String baseUrl})
      : _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseAuth _auth;
  final String _baseUrl;

  Room? _room;
  final StreamController<RoomEvent> _roomEvents = StreamController.broadcast();

  Stream<RoomEvent> get events => _roomEvents.stream;

  Room? get room => _room;

  Future<void> connect({required String sessionId}) async {
    final tokenPayload = await _mintToken(sessionId);
    final url = tokenPayload['url'] as String?;
    final token = tokenPayload['token'] as String?;
    if (url == null || token == null) {
      throw Exception('LiveKit token response missing url/token');
    }
    _room = Room();
    _room?.addListener(_handleRoomEvent);
    await _room?.connect(url, token, fastConnectOptions: FastConnectOptions());
  }

  Future<void> disconnect() async {
    _room?.removeListener(_handleRoomEvent);
    await _room?.disconnect();
    _room = null;
  }

  Future<void> publishLocalTracks({bool audio = true, bool video = true}) async {
    final room = _room;
    if (room == null) return;
    if (audio) {
      final audioTrack = await LocalAudioTrack.create();
      await room.localParticipant?.publishAudioTrack(audioTrack);
    }
    if (video) {
      final videoTrack = await LocalVideoTrack.createCameraTrack();
      await room.localParticipant?.publishVideoTrack(videoTrack);
    }
  }

  Future<void> sendData(String message) async {
    final room = _room;
    if (room == null) return;
    await room.localParticipant?.publishData(
      message.codeUnits,
      reliable: true,
    );
  }

  void _handleRoomEvent() {
    final room = _room;
    if (room == null) return;
    _roomEvents.add(RoomEvent(room));
  }

  Future<Map<String, dynamic>> _mintToken(String sessionId) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/session/mintLiveKitToken'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: '{"sessionId":"$sessionId"}',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('LiveKit token request failed: ${response.statusCode}');
    }
    return Map<String, dynamic>.from(
      response.body.isNotEmpty ? jsonDecode(response.body) : {},
    );
  }
}

class RoomEvent {
  RoomEvent(this.room);
  final Room room;
}
