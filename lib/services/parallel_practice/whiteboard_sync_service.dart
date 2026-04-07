import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'local_permissions.dart';
import 'paths.dart';

enum ClassroomBoardKind {
  sharedBoard,
  studentPrivateBoard,
  reviewBoard,
  exemplarBoard,
}

enum BoardOwnershipState {
  tutorOwned,
  studentOwned,
  coEditable,
  lockedForSubmission,
  reviewOnly,
  broadcastBase,
}

enum BoardTransientState { none, spotlight }

enum BoardSpotlightMode { none, soft, hard }

class BoardDescriptor {
  const BoardDescriptor({
    required this.boardId,
    required this.boardKind,
    required this.ownerId,
    required this.subjectStudentId,
    required this.ownershipState,
    required this.visibilityScope,
    required this.transientState,
    required this.sourceBoardId,
    required this.sourceSnapshotId,
    required this.previewEnabled,
    required this.revisionCursor,
    required this.active,
    required this.updatedAt,
  });

  final String boardId;
  final ClassroomBoardKind boardKind;
  final String? ownerId;
  final String? subjectStudentId;
  final BoardOwnershipState ownershipState;
  final String visibilityScope;
  final BoardTransientState transientState;
  final String? sourceBoardId;
  final String? sourceSnapshotId;
  final bool previewEnabled;
  final int revisionCursor;
  final bool active;
  final DateTime? updatedAt;

  factory BoardDescriptor.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return BoardDescriptor(
      boardId: doc.id,
      boardKind: _boardKindFromString(_asString(data['boardKind'])),
      ownerId: _asString(data['ownerId']),
      subjectStudentId: _asString(data['subjectStudentId']),
      ownershipState: _ownershipStateFromString(_asString(data['ownershipState'])),
      visibilityScope: _asString(data['visibilityScope']) ?? 'class',
      transientState: _transientStateFromString(_asString(data['transientState'])),
      sourceBoardId: _asString(data['sourceBoardId']),
      sourceSnapshotId: _asString(data['sourceSnapshotId']),
      previewEnabled: data['previewEnabled'] == true,
      revisionCursor: _asInt(data['revisionCursor']),
      active: data['active'] != false,
      updatedAt: _asDateTime(data['updatedAt']),
    );
  }
}

class BoardRoute {
  const BoardRoute({
    required this.participantId,
    required this.role,
    required this.currentBoardId,
    required this.currentBoardKind,
    required this.visibleBoardIds,
    required this.previewBoardIds,
    required this.writeBoardIds,
    required this.spotlightBoardId,
    required this.reviewBoardId,
    required this.baseSnapshotId,
    required this.boardMode,
    required this.focusMode,
    required this.spotlightMode,
    required this.pauseOthers,
    required this.isDeemphasized,
    required this.isPausedByTutor,
    required this.routeVersion,
    required this.active,
    required this.updatedAt,
  });

  final String participantId;
  final String role;
  final String currentBoardId;
  final ClassroomBoardKind currentBoardKind;
  final List<String> visibleBoardIds;
  final List<String> previewBoardIds;
  final List<String> writeBoardIds;
  final String? spotlightBoardId;
  final String? reviewBoardId;
  final String? baseSnapshotId;
  final String boardMode;
  final String focusMode;
  final BoardSpotlightMode spotlightMode;
  final bool pauseOthers;
  final bool isDeemphasized;
  final bool isPausedByTutor;
  final int routeVersion;
  final bool active;
  final DateTime? updatedAt;

  bool canWrite(String boardId) => writeBoardIds.contains(boardId);
  bool canSee(String boardId) => visibleBoardIds.contains(boardId);

  factory BoardRoute.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return BoardRoute(
      participantId: doc.id,
      role: _asString(data['role']) ?? 'student',
      currentBoardId: _asString(data['currentBoardId']) ?? 'shared',
      currentBoardKind: _boardKindFromString(_asString(data['currentBoardKind'])),
      visibleBoardIds: _asStringList(data['visibleBoardIds']),
      previewBoardIds: _asStringList(data['previewBoardIds']),
      writeBoardIds: _asStringList(data['writeBoardIds']),
      spotlightBoardId: _asString(data['spotlightBoardId']),
      reviewBoardId: _asString(data['reviewBoardId']),
      baseSnapshotId: _asString(data['baseSnapshotId']),
      boardMode: _asString(data['boardMode']) ?? 'sharedBoard',
      focusMode: _asString(data['focusMode']) ?? 'wholeClass',
      spotlightMode: _boardSpotlightModeFromString(_asString(data['spotlightMode'])),
      pauseOthers: data['pauseOthers'] == true,
      isDeemphasized: data['isDeemphasized'] == true,
      isPausedByTutor: data['isPausedByTutor'] == true,
      routeVersion: _asInt(data['routeVersion'], fallback: 1),
      active: data['active'] != false,
      updatedAt: _asDateTime(data['updatedAt']),
    );
  }
}

class BoardSnapshotRecord {
  const BoardSnapshotRecord({
    required this.snapshotId,
    required this.boardId,
    required this.snapshotKind,
    required this.visibilityScope,
    required this.immutable,
    required this.locked,
    required this.sourceBoardRevision,
    required this.studentId,
    required this.createdAt,
    required this.url,
    required this.storagePath,
  });

  final String snapshotId;
  final String boardId;
  final String snapshotKind;
  final String visibilityScope;
  final bool immutable;
  final bool locked;
  final int sourceBoardRevision;
  final String? studentId;
  final DateTime? createdAt;
  final String? url;
  final String? storagePath;

  factory BoardSnapshotRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return BoardSnapshotRecord(
      snapshotId: doc.id,
      boardId: _asString(data['boardId']) ?? '',
      snapshotKind: _asString(data['snapshotKind']) ?? 'review',
      visibilityScope: _asString(data['visibilityScope']) ?? 'tutorOnly',
      immutable: data['immutable'] == true,
      locked: data['locked'] == true,
      sourceBoardRevision: _asInt(data['sourceBoardRevision']),
      studentId: _asString(data['studentId']),
      createdAt: _asDateTime(data['createdAt']),
      url: _asString(data['url']),
      storagePath: _asString(data['storagePath']),
    );
  }
}

class BoardChunkRecord {
  const BoardChunkRecord({
    required this.chunkId,
    required this.boardId,
    required this.writerId,
    required this.writerRole,
    required this.seqStart,
    required this.seqEnd,
    required this.baseRevision,
    required this.chunkType,
    required this.status,
    required this.serverOrder,
    required this.events,
    required this.createdAt,
  });

  final String chunkId;
  final String boardId;
  final String writerId;
  final String writerRole;
  final int seqStart;
  final int seqEnd;
  final int baseRevision;
  final String chunkType;
  final String status;
  final int serverOrder;
  final List<Map<String, dynamic>> events;
  final DateTime? createdAt;

  factory BoardChunkRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawEvents = data['events'];
    return BoardChunkRecord(
      chunkId: doc.id,
      boardId: _asString(data['boardId']) ?? '',
      writerId: _asString(data['writerId']) ?? '',
      writerRole: _asString(data['writerRole']) ?? 'student',
      seqStart: _asInt(data['seqStart']),
      seqEnd: _asInt(data['seqEnd']),
      baseRevision: _asInt(data['baseRevision']),
      chunkType: _asString(data['chunkType']) ?? 'strokeBatch',
      status: _asString(data['status']) ?? 'pending',
      serverOrder: _asInt(data['serverOrder']),
      events: rawEvents is List
          ? rawEvents.map((event) => _asMap(event)).toList(growable: false)
          : const <Map<String, dynamic>>[],
      createdAt: _asDateTime(data['createdAt']),
    );
  }
}

class WhiteboardCommandAck {
  const WhiteboardCommandAck({
    required this.ok,
    required this.payload,
  });

  final bool ok;
  final Map<String, dynamic> payload;

  String? get snapshotId => _asString(payload['snapshotId']);
  String? get exemplarBoardId => _asString(payload['exemplarBoardId']);
}

class WhiteboardSyncService {
  WhiteboardSyncService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required String baseUrl,
  })  : _firestore = firestore,
        _auth = auth,
        _baseUrl = baseUrl;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String _baseUrl;
  final Map<String, int> _lastSeqByWriterAndBoard = HashMap();
  final Map<String, Map<String, dynamic>> _pendingChunks = HashMap();

  String nextChunkId({
    required String boardId,
    required String writerId,
    required String deviceId,
    required int seqStart,
    required int seqEnd,
  }) {
    return [boardId, writerId, deviceId, seqStart, seqEnd].join('_');
  }

  bool shouldAppend(String boardId, String writerId, int seqEnd) {
    final key = '$boardId::$writerId';
    final last = _lastSeqByWriterAndBoard[key] ?? -1;
    if (seqEnd <= last) return false;
    _lastSeqByWriterAndBoard[key] = seqEnd;
    return true;
  }

  Stream<BoardRoute?> watchBoardRoute({
    required String sessionId,
    required String participantId,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.boardRoutes)
        .doc(participantId)
        .snapshots()
        .map((doc) => doc.exists ? BoardRoute.fromDoc(doc) : null);
  }

  Stream<BoardDescriptor?> watchBoard({
    required String sessionId,
    required String boardId,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.boards)
        .doc(boardId)
        .snapshots()
        .map((doc) => doc.exists ? BoardDescriptor.fromDoc(doc) : null);
  }

  Stream<List<BoardDescriptor>> watchTutorBoardPreviews({
    required String sessionId,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.boards)
        .where('previewEnabled', isEqualTo: true)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(BoardDescriptor.fromDoc)
            .toList(growable: false));
  }

  Stream<List<BoardSnapshotRecord>> watchSnapshots({
    required String sessionId,
    String? boardId,
  }) {
    Query<Map<String, dynamic>> query = _sessionRef(sessionId)
        .collection(Paths.boardSnapshots)
        .orderBy('createdAt', descending: true);
    if (boardId != null && boardId.trim().isNotEmpty) {
      query = query.where('boardId', isEqualTo: boardId.trim());
    }
    return query.snapshots().map((snapshot) => snapshot.docs
        .map(BoardSnapshotRecord.fromDoc)
        .toList(growable: false));
  }

  Stream<List<BoardChunkRecord>> watchAcceptedChunks({
    required String sessionId,
    required String boardId,
    int afterServerOrder = 0,
    int limit = 200,
  }) {
    return _sessionRef(sessionId)
        .collection(Paths.boardEventChunks)
        .where('boardId', isEqualTo: boardId)
        .where('status', isEqualTo: 'accepted')
        .orderBy('serverOrder')
        .startAfter([afterServerOrder])
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(BoardChunkRecord.fromDoc)
            .toList(growable: false));
  }

  Future<List<BoardChunkRecord>> loadAcceptedChunks({
    required String sessionId,
    required String boardId,
    int afterServerOrder = 0,
    int limit = 200,
  }) async {
    final snapshot = await _sessionRef(sessionId)
        .collection(Paths.boardEventChunks)
        .where('boardId', isEqualTo: boardId)
        .where('status', isEqualTo: 'accepted')
        .orderBy('serverOrder')
        .startAfter([afterServerOrder])
        .limit(limit)
        .get();
    return snapshot.docs.map(BoardChunkRecord.fromDoc).toList(growable: false);
  }

  Future<String> appendChunk({
    required String sessionId,
    required String boardId,
    required String ownerId,
    required String writerId,
    required SessionRole writerRole,
    required String deviceId,
    required int seqStart,
    required int seqEnd,
    required List<Map<String, dynamic>> events,
    int baseRevision = 0,
    String chunkType = 'strokeBatch',
    String? undoGroupId,
    List<String>? targetOpIds,
  }) async {
    final chunkId = nextChunkId(
      boardId: boardId,
      writerId: writerId,
      deviceId: deviceId,
      seqStart: seqStart,
      seqEnd: seqEnd,
    );

    if (!shouldAppend(boardId, writerId, seqEnd)) {
      return chunkId;
    }

    final payload = <String, dynamic>{
      'chunkId': chunkId,
      'boardId': boardId,
      'ownerId': ownerId,
      'writerId': writerId,
      'writerRole': writerRole.name,
      'deviceId': deviceId,
      'seqStart': seqStart,
      'seqEnd': seqEnd,
      'baseRevision': baseRevision,
      'chunkType': chunkType,
      'undoGroupId': undoGroupId,
      'targetOpIds': targetOpIds ?? const <String>[],
      'events': events,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'clientEmittedAt': Timestamp.now(),
    };

    _pendingChunks[chunkId] = {
      'sessionId': sessionId,
      ...payload,
    };

    try {
      await _sessionRef(sessionId)
          .collection(Paths.boardEventChunks)
          .doc(chunkId)
          .set(payload, SetOptions(merge: true));
      _pendingChunks.remove(chunkId);
    } catch (_) {
      // Keep the pending chunk in memory so it can be replayed after reconnect.
    }

    return chunkId;
  }

  Future<void> flushPendingChunks({
    required String sessionId,
    String? boardId,
  }) async {
    final pending = _pendingChunks.entries
        .where((entry) =>
            entry.value['sessionId'] == sessionId &&
            (boardId == null || entry.value['boardId'] == boardId))
        .toList(growable: false);
    for (final entry in pending) {
      final chunkId = entry.key;
      final payload = Map<String, dynamic>.from(entry.value)..remove('sessionId');
      try {
        await _sessionRef(sessionId)
            .collection(Paths.boardEventChunks)
            .doc(chunkId)
            .set(payload, SetOptions(merge: true));
        _pendingChunks.remove(chunkId);
      } catch (_) {
        // Leave it queued for the next recovery pass.
      }
    }
  }

  Future<void> emitLaser({
    required String sessionId,
    required String userId,
    required String boardId,
    required Map<String, dynamic> payload,
  }) async {
    await _sessionRef(sessionId)
        .collection(Paths.laserEvents)
        .doc(userId)
        .set({
      'boardId': boardId,
      'payload': payload,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch + 15000,
      ),
    }, SetOptions(merge: true));
  }

  Future<WhiteboardCommandAck> freezeSnapshot({
    required String sessionId,
    required String boardId,
    required SessionRole role,
    String snapshotKind = 'review',
    bool lockBoard = false,
    String? studentId,
    String? storagePath,
    String? url,
    String? actionId,
  }) async {
    requireRole(role, {
      SessionRole.primaryTutor,
      SessionRole.coTutor,
      SessionRole.student,
    });
    final payload = await _post('/board/freezeSnapshot', {
      'sessionId': sessionId,
      'boardId': boardId,
      'snapshotKind': snapshotKind,
      'lockBoard': lockBoard,
      if (studentId != null && studentId.trim().isNotEmpty) 'studentId': studentId.trim(),
      if (storagePath != null && storagePath.trim().isNotEmpty)
        'storagePath': storagePath.trim(),
      if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
      if (actionId != null && actionId.trim().isNotEmpty) 'actionId': actionId.trim(),
    });
    return WhiteboardCommandAck(ok: payload['ok'] != false, payload: payload);
  }

  Future<WhiteboardCommandAck> spotlightStudentBoard({
    required String sessionId,
    required String studentId,
    required SessionRole role,
    bool observeOnly = false,
    BoardSpotlightMode spotlightMode = BoardSpotlightMode.hard,
    bool pauseOthers = false,
    bool deEmphasizeOthers = true,
    String? reason,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor, SessionRole.coTutor});
    final payload = await _post('/board/spotlight', {
      'sessionId': sessionId,
      'studentId': studentId,
      'observeOnly': observeOnly,
      'spotlightMode': _boardSpotlightModeToWire(spotlightMode),
      'pauseOthers': pauseOthers,
      'deEmphasizeOthers': deEmphasizeOthers,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      if (actionId != null && actionId.trim().isNotEmpty) 'actionId': actionId.trim(),
    });
    return WhiteboardCommandAck(ok: payload['ok'] != false, payload: payload);
  }

  Future<WhiteboardCommandAck> softSpotlightStudentBoard({
    required String sessionId,
    required String studentId,
    required SessionRole role,
    bool observeOnly = false,
    bool deEmphasizeOthers = true,
    String? reason,
    String? actionId,
  }) {
    return spotlightStudentBoard(
      sessionId: sessionId,
      studentId: studentId,
      role: role,
      observeOnly: observeOnly,
      spotlightMode: BoardSpotlightMode.soft,
      pauseOthers: false,
      deEmphasizeOthers: deEmphasizeOthers,
      reason: reason,
      actionId: actionId,
    );
  }

  Future<WhiteboardCommandAck> hardSpotlightStudentBoard({
    required String sessionId,
    required String studentId,
    required SessionRole role,
    bool observeOnly = false,
    bool pauseOthers = false,
    bool deEmphasizeOthers = true,
    String? reason,
    String? actionId,
  }) {
    return spotlightStudentBoard(
      sessionId: sessionId,
      studentId: studentId,
      role: role,
      observeOnly: observeOnly,
      spotlightMode: BoardSpotlightMode.hard,
      pauseOthers: pauseOthers,
      deEmphasizeOthers: deEmphasizeOthers,
      reason: reason,
      actionId: actionId,
    );
  }

  Future<WhiteboardCommandAck> broadcastSnapshotToClass({
    required String sessionId,
    required String studentId,
    required String snapshotId,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final payload = await _post('/board/broadcastSnapshot', {
      'sessionId': sessionId,
      'studentId': studentId,
      'snapshotId': snapshotId,
      if (actionId != null && actionId.trim().isNotEmpty) 'actionId': actionId.trim(),
    });
    return WhiteboardCommandAck(ok: payload['ok'] != false, payload: payload);
  }

  Future<WhiteboardCommandAck> markSnapshotExemplar({
    required String sessionId,
    required String snapshotId,
    required SessionRole role,
    String? actionId,
  }) async {
    requireRole(role, {SessionRole.primaryTutor});
    final payload = await _post('/session/markExemplar', {
      'sessionId': sessionId,
      'snapshotId': snapshotId,
      if (actionId != null && actionId.trim().isNotEmpty) 'actionId': actionId.trim(),
    });
    return WhiteboardCommandAck(ok: payload['ok'] != false, payload: payload);
  }

  DocumentReference<Map<String, dynamic>> _sessionRef(String sessionId) {
    return _firestore.collection(Paths.sessions).doc(sessionId);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

String? _asString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _asDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry('$key', item));
  }
  return <String, dynamic>{};
}

List<String> _asStringList(dynamic value) {
  if (value is Iterable) {
    return value
        .map((dynamic item) => _asString(item))
        .whereType<String>()
        .toList(growable: false);
  }
  return const <String>[];
}

ClassroomBoardKind _boardKindFromString(String? value) {
  switch (value) {
    case 'studentPrivateBoard':
      return ClassroomBoardKind.studentPrivateBoard;
    case 'reviewBoard':
      return ClassroomBoardKind.reviewBoard;
    case 'exemplarBoard':
      return ClassroomBoardKind.exemplarBoard;
    case 'sharedBoard':
    default:
      return ClassroomBoardKind.sharedBoard;
  }
}

BoardOwnershipState _ownershipStateFromString(String? value) {
  switch (value) {
    case 'studentOwned':
      return BoardOwnershipState.studentOwned;
    case 'coEditable':
      return BoardOwnershipState.coEditable;
    case 'lockedForSubmission':
      return BoardOwnershipState.lockedForSubmission;
    case 'reviewOnly':
      return BoardOwnershipState.reviewOnly;
    case 'broadcastBase':
      return BoardOwnershipState.broadcastBase;
    case 'tutorOwned':
    default:
      return BoardOwnershipState.tutorOwned;
  }
}

BoardTransientState _transientStateFromString(String? value) {
  switch (value) {
    case 'spotlight':
      return BoardTransientState.spotlight;
    case 'none':
    default:
      return BoardTransientState.none;
  }
}

BoardSpotlightMode _boardSpotlightModeFromString(String? value) {
  switch (value) {
    case 'soft':
      return BoardSpotlightMode.soft;
    case 'hard':
      return BoardSpotlightMode.hard;
    case 'none':
    default:
      return BoardSpotlightMode.none;
  }
}

String _boardSpotlightModeToWire(BoardSpotlightMode value) {
  switch (value) {
    case BoardSpotlightMode.soft:
      return 'soft';
    case BoardSpotlightMode.hard:
      return 'hard';
    case BoardSpotlightMode.none:
      return 'none';
  }
}
