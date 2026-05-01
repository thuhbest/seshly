import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/parallel_practice/classroom_orchestrator_service.dart';
import '../../../services/parallel_practice/classroom_reliability_service.dart';
import '../../../services/parallel_practice/live_call_router.dart';
import '../../../services/parallel_practice/livekit_service.dart';
import '../../../services/parallel_practice/local_permissions.dart';
import '../../../services/parallel_practice/p2p_webrtc_service.dart';
import '../../../services/parallel_practice/session_service.dart';
import '../../../services/parallel_practice/whiteboard_sync_service.dart';
import '../models/session_mode.dart';
import '../widgets/give_task_modal.dart';
import '../widgets/mode_switch_pill.dart';
import '../widgets/right_rail.dart';
import '../widgets/shared_board.dart';
import '../widgets/student_grid.dart';
import '../widgets/student_tile.dart';
import 'session_wrap_view.dart';

class ParallelPracticeView extends StatefulWidget {
  const ParallelPracticeView({
    super.key,
    this.sessionId,
    this.title = 'Parallel Practice',
    this.subject = 'General',
    this.role = SessionRole.primaryTutor,
  });

  final String? sessionId;
  final String title;
  final String subject;
  final SessionRole role;

  @override
  State<ParallelPracticeView> createState() => _ParallelPracticeViewState();
}

class _ParallelPracticeViewState extends State<ParallelPracticeView> {
  late final SessionService _sessionService;
  late final LiveCallRouter _callRouter;
  late final ClassroomOrchestratorService _orchestratorService;
  late final WhiteboardSyncService _whiteboardService;
  late final ClassroomReliabilityService _reliabilityService;

  final Color backgroundColor = const Color(0xFF0F142B);
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);

  String _sessionId = '';
  bool _isBootstrapping = true;
  bool _isRecovering = false;
  String? _bootstrapError;
  ConnectionStateStatus _connectionState = ConnectionStateStatus.idle;
  Timer? _heartbeatTimer;
  StreamSubscription<ConnectionStateStatus>? _connectionSub;
  int _heartbeatSeq = 0;

  @override
  void initState() {
    super.initState();
    final baseUrl = const String.fromEnvironment(
      'PARALLEL_PRACTICE_API_BASE_V2',
      defaultValue:
          'https://europe-west2-seshly-9e638.cloudfunctions.net/parallelPracticeV2Api',
    );
    _sessionService = SessionService(auth: FirebaseAuth.instance, baseUrl: baseUrl);
    _callRouter = LiveCallRouter(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
      p2pService: P2PWebRtcService(firestore: FirebaseFirestore.instance),
      liveKitService: LiveKitService(auth: FirebaseAuth.instance, baseUrl: baseUrl),
    );
    _orchestratorService = ClassroomOrchestratorService(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      baseUrl: baseUrl,
    );
    _whiteboardService = WhiteboardSyncService(
      firestore: FirebaseFirestore.instance,
      auth: FirebaseAuth.instance,
      baseUrl: baseUrl,
    );
    _reliabilityService = ClassroomReliabilityService(
      auth: FirebaseAuth.instance,
      firestore: FirebaseFirestore.instance,
      baseUrl: baseUrl,
    );
    _connectionSub = _callRouter.connectionStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _connectionState = state);
      if (state == ConnectionStateStatus.disconnected && _sessionId.isNotEmpty) {
        _recoverSession();
      }
    });
    _bootstrapSession();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _connectionSub?.cancel();
    _callRouter.dispose();
    super.dispose();
  }

  Future<void> _bootstrapSession() async {
    setState(() {
      _isBootstrapping = true;
      _bootstrapError = null;
    });
    try {
      String sessionId = widget.sessionId?.trim() ?? '';
      if (sessionId.isEmpty) {
        final response = await _sessionService.createSession(
          title: widget.title,
          subject: widget.subject,
        );
        sessionId = (response['sessionId'] ?? '').toString();
      } else {
        try {
          await _sessionService.joinSession(sessionId);
        } catch (_) {
          // Treat rejoin conflicts as non-fatal; state recovery handles the rest.
        }
      }
      if (!mounted || sessionId.isEmpty) return;
      await _callRouter.bindSession(sessionId: sessionId);
      _startHeartbeat(sessionId);
      setState(() {
        _sessionId = sessionId;
        _isBootstrapping = false;
        _connectionState = ConnectionStateStatus.connected;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
        _bootstrapError = error.toString();
      });
    }
  }

  void _startHeartbeat(String sessionId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (_sessionId.isEmpty || _sessionId != sessionId) return;
      try {
        _heartbeatSeq += 1;
        await _reliabilityService.heartbeat(
          sessionId: sessionId,
          heartbeatSeq: _heartbeatSeq,
          presenceState: 'online',
          networkQuality: _connectionState == ConnectionStateStatus.connected ? 'stable' : 'weak',
          mediaHealth: _connectionState == ConnectionStateStatus.connected ? 'stable' : 'recovering',
          transportState: _connectionState.name,
          isReconnect: _isRecovering,
        );
      } catch (_) {
        if (_connectionState != ConnectionStateStatus.disconnected) {
          setState(() => _connectionState = ConnectionStateStatus.disconnected);
        }
      }
    });
  }

  Future<void> _recoverSession() async {
    if (_isRecovering || _sessionId.isEmpty) return;
    setState(() => _isRecovering = true);
    try {
      await _reliabilityService.recoverState(
        sessionId: _sessionId,
        networkQuality: 'recovering',
        mediaHealth: 'recovering',
        forceRejoin: true,
      );
      await _whiteboardService.flushPendingChunks(sessionId: _sessionId);
      await _callRouter.bindSession(sessionId: _sessionId);
    } catch (_) {
      // Leave the UI in reconnecting state. Another heartbeat or manual retry can recover it.
    } finally {
      if (mounted) {
        setState(() {
          _isRecovering = false;
          _connectionState = ConnectionStateStatus.connected;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: tealAccent),
        ),
      );
    }

    if (_bootstrapError != null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 42),
                const SizedBox(height: 12),
                Text(
                  'Classroom failed to start.\n$_bootstrapError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _bootstrapSession,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
    final canLeadClass = widget.role == SessionRole.primaryTutor;
    final canTutor = widget.role == SessionRole.primaryTutor || widget.role == SessionRole.coTutor;

    final isWide = MediaQuery.of(context).size.width >= 900;

    return StreamBuilder<ClassroomState>(
      stream: _orchestratorService.watchState(_sessionId),
      builder: (context, stateSnapshot) {
        final state = stateSnapshot.data ?? ClassroomState.empty;
        return StreamBuilder<List<ClassroomParticipantState>>(
          stream: _orchestratorService.watchParticipants(_sessionId),
          builder: (context, participantsSnapshot) {
            final participants = participantsSnapshot.data ?? const <ClassroomParticipantState>[];
            return StreamBuilder<BoardRoute?>(
              stream: _whiteboardService.watchBoardRoute(
                sessionId: _sessionId,
                participantId: uid,
              ),
              builder: (context, routeSnapshot) {
                final boardRoute = routeSnapshot.data;
                return StreamBuilder<ReliabilityMetricsSnapshot>(
                  stream: _reliabilityService.watchMetrics(_sessionId),
                  builder: (context, reliabilitySnapshot) {
                    final reliability = reliabilitySnapshot.data ?? ReliabilityMetricsSnapshot.empty;
                    final sessionMode = _sessionModeFromState(state);
                    final studentCards = _buildStudentCards(participants, state);

                    return Scaffold(
                      backgroundColor: backgroundColor,
                      body: Column(
                        children: [
                          _buildTopBar(state, reliability, sessionMode, canLeadClass),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildMainCanvas(
                                    state: state,
                                    boardRoute: boardRoute,
                                    reliability: reliability,
                                    students: studentCards,
                                    canLeadClass: canLeadClass,
                                    canTutor: canTutor,
                                  ),
                                ),
                                if (isWide)
                                  RightRail(
                                    sessionId: _sessionId,
                                    activeTaskId: state.activeTaskId,
                                  ),
                              ],
                            ),
                          ),
                          _buildBottomBar(state, boardRoute),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTopBar(
    ClassroomState state,
    ReliabilityMetricsSnapshot reliability,
    SessionMode sessionMode,
    bool canLeadClass,
  ) {
    final timerLabel = _timerLabel(state.timerEndAt);
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: cardColor),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    widget.subject,
                    _sessionId,
                    if (timerLabel != null) timerLabel,
                  ].join(' • '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 11),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 220,
            child: ModeSwitchPill(
              currentMode: sessionMode,
              onChanged: canLeadClass ? (mode) => _handleModeChange(mode, state) : (_) {},
            ),
          ),
          const SizedBox(width: 14),
          _buildConnectionIndicator(reliability),
          const SizedBox(width: 12),
          if (_isRecovering)
            Text(
              'Recovering…',
              style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.9), fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildMainCanvas({
    required ClassroomState state,
    required BoardRoute? boardRoute,
    required ReliabilityMetricsSnapshot reliability,
    required List<ClassroomStudentTileData> students,
    required bool canLeadClass,
    required bool canTutor,
  }) {
    switch (_sessionModeFromState(state)) {
      case SessionMode.teach:
        return SharedBoard(
          title: 'Teach All',
          subtitle: 'Shared board is live for the whole class.',
          boardId: boardRoute?.currentBoardId ?? state.activeBoardRef,
          modeLabel: 'Teach mode',
          canAnnotate: state.classLock,
          isLive: _connectionState == ConnectionStateStatus.connected,
          secondaryLabel: state.studentAnnotateEnabled ? 'Students can annotate' : 'Tutor-controlled',
          details: [
            'Call mode: ${state.callMode.toUpperCase()}',
            'Focus: ${state.focusMode.name}',
            'Media profile: ${reliability.recommendedMediaProfile}',
          ],
        );
      case SessionMode.practice:
        return StudentGrid(
          students: students,
          onSoftSpotlight:
              canTutor ? (student) => _softSpotlight(student.studentId) : null,
          onHardSpotlight:
              canLeadClass ? (student) => _hardSpotlight(student.studentId) : null,
          onBroadcast:
              canLeadClass ? (student) => _broadcastStudentBoard(student) : null,
        );
      case SessionMode.review:
        return SharedBoard(
          title: state.spotlight.active ? 'Spotlight Review' : 'Review Board',
          subtitle: state.attentionTarget == null
              ? 'Collected work is ready for marking and explanation.'
              : 'Discussing ${state.attentionTarget} with the class.',
          boardId: state.activeBoardRef ?? boardRoute?.currentBoardId,
          modeLabel: 'Review mode',
          canAnnotate: true,
          isLive: _connectionState == ConnectionStateStatus.connected,
          secondaryLabel: state.spotlight.active
              ? '${state.spotlight.mode.name} spotlight'
              : 'Whole-class review',
          details: [
            'Collected snapshots: ${state.submissionSummary.collectedSnapshotCount}',
            'Submitted: ${state.submissionSummary.submittedStudentCount}/${state.submissionSummary.expectedStudentCount}',
            if (state.attentionTarget != null) 'Attention: ${state.attentionTarget}',
          ],
        );
    }
  }

  Widget _buildBottomBar(ClassroomState state, BoardRoute? boardRoute) {
    final canLeadClass = widget.role == SessionRole.primaryTutor;
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: cardColor),
      child: Row(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.mic_none_rounded, color: Colors.white),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.videocam_outlined, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              boardRoute == null
                  ? 'Waiting for board routing.'
                  : 'Board ${boardRoute.currentBoardId} • ${boardRoute.boardMode} • route v${boardRoute.routeVersion}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          if (canLeadClass && _sessionModeFromState(state) != SessionMode.practice) ...[
            _actionButton(
              label: 'Give Task',
              color: tealAccent,
              onPressed: _giveTask,
              textColor: backgroundColor,
            ),
            const SizedBox(width: 12),
          ],
          if (canLeadClass && _sessionModeFromState(state) == SessionMode.practice) ...[
            _actionButton(
              label: 'Collect Work',
              color: Colors.white12,
              onPressed: () => _collectWork(),
            ),
            const SizedBox(width: 12),
          ],
          if (canLeadClass && state.spotlight.active) ...[
            _actionButton(
              label: 'Return to Class',
              color: Colors.white12,
              onPressed: () => _orchestratorService.returnToClass(
                sessionId: _sessionId,
                role: widget.role,
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (canLeadClass)
            _actionButton(
              label: 'End Session',
              color: Colors.redAccent,
              onPressed: _showEndSessionDialog,
            ),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(ReliabilityMetricsSnapshot reliability) {
    Color dotColor;
    String label;
    switch (_connectionState) {
      case ConnectionStateStatus.connected:
        dotColor = reliability.weakConnectionCount > 0 ? Colors.orangeAccent : tealAccent;
        label = reliability.weakConnectionCount > 0 ? 'Live • weak links' : 'Live';
        break;
      case ConnectionStateStatus.connecting:
        dotColor = Colors.orangeAccent;
        label = 'Connecting';
        break;
      case ConnectionStateStatus.disconnected:
        dotColor = Colors.redAccent;
        label = 'Reconnect';
        break;
      case ConnectionStateStatus.idle:
        dotColor = Colors.white38;
        label = 'Idle';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
    Color textColor = Colors.white,
  }) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }

  Future<void> _handleModeChange(SessionMode mode, ClassroomState state) async {
    if (_sessionId.isEmpty) return;
    if (mode == SessionMode.practice) {
      await _giveTask();
      return;
    }
    if (mode == SessionMode.review) {
      if (state.activeTaskId != null && !state.submissionSummary.collected) {
        await _collectWork();
        return;
      }
      await _sessionService.setMode(
        sessionId: _sessionId,
        mode: 'review',
        role: widget.role,
      );
      return;
    }
    await _orchestratorService.teachAll(
      sessionId: _sessionId,
      role: widget.role,
      classLock: true,
    );
  }

  Future<void> _giveTask() async {
    if (_sessionId.isEmpty) return;
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GiveTaskModal(),
    );
    if (payload == null || payload['prompt'] == null || (payload['prompt'] as String).trim().isEmpty) {
      return;
    }
    await _orchestratorService.sendClasswork(
      sessionId: _sessionId,
      role: widget.role,
      taskPayload: payload,
    );
  }

  Future<void> _collectWork() {
    return _orchestratorService.collectTaskWork(
      sessionId: _sessionId,
      role: widget.role,
    );
  }

  Future<void> _softSpotlight(String studentId) {
    return _orchestratorService.softSpotlightStudent(
      sessionId: _sessionId,
      studentId: studentId,
      role: widget.role,
      observeOnly: true,
      deEmphasizeOthers: true,
      reason: 'soft_spotlight',
    );
  }

  Future<void> _hardSpotlight(String studentId) {
    return _orchestratorService.hardSpotlightStudent(
      sessionId: _sessionId,
      studentId: studentId,
      role: widget.role,
      observeOnly: false,
      pauseOthers: false,
      deEmphasizeOthers: true,
      reason: 'jump_in',
    );
  }

  Future<void> _broadcastStudentBoard(ClassroomStudentTileData student) async {
    if (student.boardId == null || student.boardId!.isEmpty) return;
    final snapshotAck = await _whiteboardService.freezeSnapshot(
      sessionId: _sessionId,
      boardId: student.boardId!,
      role: widget.role,
      snapshotKind: 'review',
      lockBoard: false,
      studentId: student.studentId,
    );
    final snapshotId = snapshotAck.snapshotId;
    if (snapshotId == null || snapshotId.isEmpty) return;
    await _orchestratorService.showStudentBoardToGroup(
      sessionId: _sessionId,
      studentId: student.studentId,
      snapshotId: snapshotId,
      role: widget.role,
    );
  }

  void _showEndSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: const Text('End session?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This closes the classroom and queues the structured wrap pack.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _orchestratorService.endSessionWithStructuredOutputs(
                sessionId: _sessionId,
                role: widget.role,
              );
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SessionWrapView(sessionId: _sessionId),
                ),
              );
            },
            child: const Text('End', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  List<ClassroomStudentTileData> _buildStudentCards(
    List<ClassroomParticipantState> participants,
    ClassroomState state,
  ) {
    final students = participants.where((participant) => participant.role == 'student');
    return students.map((student) {
      final displayName = (student.data['displayName'] ??
              student.data['name'] ??
              student.data['fullName'] ??
              student.data['email'] ??
              student.participantId)
          .toString();
      final spotlighted = state.attentionTarget == student.participantId ||
          student.visibilityState == ParticipantVisibilityState.spotlighted;
      final paused = student.data['workPaused'] == true;
      final focused = spotlighted ||
          student.focusState == ClassroomParticipantFocusState.underIntervention ||
          student.focusState == ClassroomParticipantFocusState.presentingToClass;
      final interventionLabel = _interventionLabel(student);
      final statusLabel = paused
          ? 'Paused'
          : spotlighted
              ? 'Spotlight'
              : interventionLabel;
      final progress = _progressForStudent(student, state);
      return ClassroomStudentTileData(
        studentId: student.participantId,
        name: displayName,
        statusLabel: statusLabel,
        progress: progress,
        focused: focused,
        spotlighted: spotlighted,
        paused: paused,
        deEmphasized: student.data['deemphasized'] == true,
        interventionLabel: interventionLabel,
        boardId: 'student_${student.participantId}',
        previewLabel: state.activeTaskId == null
            ? 'Waiting for classwork'
            : 'Task ${state.activeTaskId}',
      );
    }).toList(growable: false);
  }

  double _progressForStudent(
    ClassroomParticipantState student,
    ClassroomState state,
  ) {
    if (student.focusState == ClassroomParticipantFocusState.presentingToClass) {
      return 1;
    }
    if (student.interventionState == InterventionState.correctionSent) {
      return 0.9;
    }
    if (student.interventionState == InterventionState.tutorIntervening) {
      return 0.65;
    }
    if (state.submissionSummary.expectedStudentCount > 0 &&
        state.submissionSummary.submittedStudentCount > 0) {
      return state.submissionSummary.submittedStudentCount /
          state.submissionSummary.expectedStudentCount;
    }
    if (student.focusState == ClassroomParticipantFocusState.privateWork) {
      return 0.55;
    }
    return 0.25;
  }

  String _interventionLabel(ClassroomParticipantState participant) {
    switch (participant.interventionState) {
      case InterventionState.nudged:
        return 'Hint sent';
      case InterventionState.tutorObserving:
        return 'Tutor observing';
      case InterventionState.tutorIntervening:
        return 'Tutor intervening';
      case InterventionState.correctionSent:
        return 'Correction sent';
      case InterventionState.none:
        break;
    }

    switch (participant.focusState) {
      case ClassroomParticipantFocusState.privateWork:
        return 'Working privately';
      case ClassroomParticipantFocusState.underIntervention:
      case ClassroomParticipantFocusState.inIntervention:
        return 'Needs attention';
      case ClassroomParticipantFocusState.presentingToClass:
      case ClassroomParticipantFocusState.presentingReview:
        return 'Presenting';
      case ClassroomParticipantFocusState.inReview:
        return 'Reviewing';
      case ClassroomParticipantFocusState.monitoringGrid:
        return 'Monitoring';
      case ClassroomParticipantFocusState.inClass:
        return 'In class';
    }
  }

  SessionMode _sessionModeFromState(ClassroomState state) {
    switch (state.roomMode) {
      case ClassroomRoomMode.practice:
        return SessionMode.practice;
      case ClassroomRoomMode.review:
        return SessionMode.review;
      case ClassroomRoomMode.teach:
        return SessionMode.teach;
    }
  }

  String? _timerLabel(DateTime? timerEndAt) {
    if (timerEndAt == null) return null;
    final remaining = timerEndAt.difference(DateTime.now());
    final seconds = remaining.inSeconds;
    if (seconds <= 0) return 'Timer: done';
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return 'Timer $minutes:$secs';
  }
}
