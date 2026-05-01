import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/parallel_practice/paths.dart';
import 'sesh_ai_panel.dart';

class RightRail extends StatefulWidget {
  const RightRail({super.key, this.sessionId, this.activeTaskId});

  final String? sessionId;
  final String? activeTaskId;

  @override
  State<RightRail> createState() => _RightRailState();
}

class _RightRailState extends State<RightRail> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF00C09E),
            tabs: const [Tab(text: 'AI'), Tab(text: 'Flow')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SeshAIPanel(sessionId: widget.sessionId),
                _ClassroomFlowPanel(
                  sessionId: widget.sessionId,
                  activeTaskId: widget.activeTaskId,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassroomFlowPanel extends StatelessWidget {
  const _ClassroomFlowPanel({
    required this.sessionId,
    required this.activeTaskId,
  });

  final String? sessionId;
  final String? activeTaskId;

  @override
  Widget build(BuildContext context) {
    if (sessionId == null || sessionId!.isEmpty) {
      return const Center(
        child: Text('Waiting for classroom session.', style: TextStyle(color: Colors.white38)),
      );
    }

    final sessionRef = FirebaseFirestore.instance.collection(Paths.sessions).doc(sessionId);
    final taskQuery = sessionRef.collection(Paths.tasks).orderBy('createdAt', descending: true).limit(4);
    final momentQuery = sessionRef.collection(Paths.aiMoments).orderBy('createdAt', descending: true).limit(5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelTitle('Active task'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: taskQuery.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _emptyCard('No classwork has been assigned yet.');
              }
              final tasks = snapshot.data!.docs;
              return Column(
                children: tasks.map((doc) {
                  final data = doc.data();
                  final isActive = doc.id == activeTaskId || data['status'] == 'active';
                  return _flowCard(
                    title: (data['prompt'] ?? 'Untitled task').toString(),
                    subtitle: [
                      if (data['submissionFormat'] != null)
                        'Format: ${data['submissionFormat']}',
                      if (data['timerSec'] != null) 'Timer: ${(data['timerSec'] as num).round()}s',
                    ].join(' • '),
                    accent: isActive ? const Color(0xFF00C09E) : Colors.white24,
                    trailing: isActive ? 'Live' : (data['status'] ?? 'Queued').toString(),
                  );
                }).toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 20),
          _panelTitle('Recent classroom moments'),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: momentQuery.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _emptyCard('AI moments and spotlight markers appear here.');
              }
              final moments = snapshot.data!.docs;
              return Column(
                children: moments.map((doc) {
                  final data = doc.data();
                  return _flowCard(
                    title: (data['type'] ?? 'moment').toString(),
                    subtitle: [
                      if (data['studentId'] != null) 'Student: ${data['studentId']}',
                      if (data['importance'] != null) 'Importance: ${data['importance']}',
                    ].join(' • '),
                    accent: const Color(0xFFFFD166),
                    trailing: (data['status'] ?? 'Logged').toString(),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _panelTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }

  Widget _flowCard({
    required String title,
    required String subtitle,
    required Color accent,
    required String trailing,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B).withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
