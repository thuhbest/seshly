import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class P2PWebRtcService {
  P2PWebRtcService({required FirebaseFirestore firestore}) : _firestore = firestore;

  final FirebaseFirestore _firestore;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final StreamController<MediaStream> _remoteStreamController =
      StreamController.broadcast();
  final StreamController<RTCPeerConnectionState> _connectionStateController =
      StreamController.broadcast();

  Stream<MediaStream> get remoteStream => _remoteStreamController.stream;
  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _signalSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _iceSub;
  // ignore: unused_field
  String? _sessionId;
  // ignore: unused_field
  String? _pairId;
  // ignore: unused_field
  String? _selfUid;
  bool _isCaller = false;

  Future<void> connect({
    required String sessionId,
    required String selfUid,
    required String pairId,
    required List<String> memberIds,
    required bool isCaller,
    List<String>? stunServers,
  }) async {
    _sessionId = sessionId;
    _selfUid = selfUid;
    _pairId = pairId;
    _isCaller = isCaller;

    final config = {
      'iceServers': [
        {'urls': stunServers ?? ['stun:stun.l.google.com:19302']}
      ]
    };
    _pc = await createPeerConnection(config);

    _pc?.onConnectionState = (state) {
      _connectionStateController.add(state);
    };

    _pc?.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreamController.add(event.streams.first);
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': true,
    });
    for (final track in _localStream!.getTracks()) {
      await _pc?.addTrack(track, _localStream!);
    }

    final signalDoc = _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('webrtcSignaling')
        .doc(pairId);
    final normalizedMembers = [...memberIds]..sort();
    await signalDoc.set({
      'members': normalizedMembers,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _signalSub = signalDoc.snapshots().listen((snapshot) async {
      final data = snapshot.data() ?? {};
      if (!_isCaller && data['offer'] != null) {
        await _pc?.setRemoteDescription(
          RTCSessionDescription(data['offer']['sdp'], data['offer']['type']),
        );
        final answer = await _pc?.createAnswer();
        if (answer == null) return;
        await _pc?.setLocalDescription(answer);
        await signalDoc.set({
          'answer': answer.toMap(),
          'members': normalizedMembers,
          'from': selfUid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (_isCaller && data['answer'] != null) {
        await _pc?.setRemoteDescription(
          RTCSessionDescription(data['answer']['sdp'], data['answer']['type']),
        );
      }
    });

    _pc?.onIceCandidate = (candidate) async {
      await signalDoc.collection('iceCandidates').add({
        'from': selfUid,
        'members': normalizedMembers,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'createdAt': FieldValue.serverTimestamp(),
      });
    };

    _iceSub = signalDoc
        .collection('iceCandidates')
        .where('from', isNotEqualTo: selfUid)
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() ?? {};
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          await _pc?.addCandidate(candidate);
        }
      }
    });

    if (_isCaller) {
      final offer = await _pc?.createOffer();
      if (offer == null) return;
      await _pc?.setLocalDescription(offer);
      await signalDoc.set({
        'offer': offer.toMap(),
        'members': normalizedMembers,
        'from': selfUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> disconnect() async {
    await _signalSub?.cancel();
    await _iceSub?.cancel();
    await _pc?.close();
    await _localStream?.dispose();
    _pc = null;
    _localStream = null;
    _sessionId = null;
    _pairId = null;
    _selfUid = null;
  }
}
