import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'livekit_service.dart';
import 'p2p_webrtc_service.dart';
import 'paths.dart';

enum CallMode { p2p, sfu }

enum ConnectionStateStatus { idle, connecting, connected, disconnected }

class LiveCallRouter {
  LiveCallRouter({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required P2PWebRtcService p2pService,
    required LiveKitService liveKitService,
  })  : _firestore = firestore,
        _auth = auth,
        _p2pService = p2pService,
        _liveKitService = liveKitService;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final P2PWebRtcService _p2pService;
  final LiveKitService _liveKitService;

  final StreamController<ConnectionStateStatus> _connectionStateController =
      StreamController.broadcast();

  Stream<ConnectionStateStatus> get connectionStateStream =>
      _connectionStateController.stream;

  Stream<QuerySnapshot<Map<String, dynamic>>> participantsStream(String sessionId) {
    return _firestore
        .collection(Paths.sessions)
        .doc(sessionId)
        .collection(Paths.participants)
        .snapshots(includeMetadataChanges: true);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> sessionStateStream(String sessionId) {
    return _firestore
        .collection(Paths.sessions)
        .doc(sessionId)
        .collection(Paths.sessionState)
        .doc('sessionState')
        .snapshots(includeMetadataChanges: true);
  }

  Stream<RoomEvent> get liveKitEvents => _liveKitService.events;

  CallMode? _currentMode;
  int _currentVersion = -1;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _stateSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _participantsSub;
  Timer? _migrationDebounce;
  String? _boundSessionId;
  List<String> _participantIds = [];
  bool _isApplyingMode = false;

  Future<void> bindSession({required String sessionId}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('Not signed in');
    }

    _connectionStateController.add(ConnectionStateStatus.connecting);
    _boundSessionId = sessionId;
    await _stateSub?.cancel();
    await _participantsSub?.cancel();
    _migrationDebounce?.cancel();

    _participantsSub = participantsStream(sessionId).listen((snapshot) {
      final ids = <String>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final joinState = (data['joinState'] ?? 'joined').toString();
        if (joinState == 'left') continue;
        ids.add(doc.id);
      }
      _participantIds = ids;
    });

    _stateSub = sessionStateStream(sessionId).listen((snapshot) async {
      final data = snapshot.data() ?? {};
      final callModeRaw = (data['callMode'] ?? 'p2p').toString();
      final version = (data['callModeVersion'] ?? 0) as int;
      final callMode = callModeRaw == 'sfu' ? CallMode.sfu : CallMode.p2p;

      if (_currentMode == callMode && _currentVersion == version) return;
      _migrationDebounce?.cancel();
      _migrationDebounce = Timer(const Duration(milliseconds: 450), () async {
        await _applyCallMode(
          sessionId: sessionId,
          uid: uid,
          callMode: callMode,
          version: version,
        );
      });
    }, onError: (_) {
      _connectionStateController.add(ConnectionStateStatus.disconnected);
    });
  }

  Future<void> _applyCallMode({
    required String sessionId,
    required String uid,
    required CallMode callMode,
    required int version,
  }) async {
    if (_isApplyingMode) return;
    if (_boundSessionId != sessionId) return;
    _isApplyingMode = true;
    _connectionStateController.add(ConnectionStateStatus.connecting);
    try {
      if (callMode == CallMode.p2p) {
        if (_participantIds.length < 2) return;
        final sorted = [..._participantIds]..sort();
        final pairId = '${sorted.first}_${sorted.last}';
        final isCaller = uid == sorted.first;
        await _liveKitService.disconnect();
        await _p2pService.connect(
          sessionId: sessionId,
          selfUid: uid,
          pairId: pairId,
          memberIds: sorted,
          isCaller: isCaller,
        );
      } else {
        await _p2pService.disconnect();
        await _liveKitService.connect(sessionId: sessionId);
        await _liveKitService.publishLocalTracks();
      }
      _currentMode = callMode;
      _currentVersion = version;
      _connectionStateController.add(ConnectionStateStatus.connected);
    } catch (_) {
      _connectionStateController.add(ConnectionStateStatus.disconnected);
    } finally {
      _isApplyingMode = false;
    }
  }

  Future<void> dispose() async {
    _migrationDebounce?.cancel();
    await _stateSub?.cancel();
    await _participantsSub?.cancel();
    await _p2pService.disconnect();
    await _liveKitService.disconnect();
    await _connectionStateController.close();
  }
}
