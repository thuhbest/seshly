import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/mentorship_service.dart';

class MentorDashboardView extends StatefulWidget {
  final MentorshipService service;
  final void Function(String userId, String userName) onMessageUser;

  const MentorDashboardView({
    super.key,
    required this.service,
    required this.onMessageUser,
  });

  @override
  State<MentorDashboardView> createState() => _MentorDashboardViewState();
}

class _MentorDashboardViewState extends State<MentorDashboardView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);
  final Color backgroundColor = const Color(0xFF0F142B);

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not scheduled';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  Color _riskColor(int score) {
    if (score >= 70) return Colors.redAccent;
    if (score >= 40) return Colors.amberAccent;
    return const Color(0xFF00C09E);
  }

  String _riskLabel(int score) {
    if (score >= 70) return 'High';
    if (score >= 40) return 'Medium';
    return 'Stable';
  }

  Map<String, int> _computeScores(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) {
      return {'reliability': 0, 'engagement': 0, 'impact': 0, 'overall': 0};
    }

    final now = DateTime.now();
    int recentInteractions = 0;
    int riskTotal = 0;
    int streakTotal = 0;

    for (final doc in docs) {
      final data = doc.data();
      final riskScore = (data['riskScore'] as num?)?.toInt() ?? 0;
      final checkInStreak = (data['checkInStreak'] as num?)?.toInt() ?? 0;
      final lastInteraction = data['lastInteractionAt'] as Timestamp?;

      riskTotal += riskScore;
      streakTotal += checkInStreak;

      if (lastInteraction != null) {
        final diff = now.difference(lastInteraction.toDate()).inDays;
        if (diff <= 7) {
          recentInteractions += 1;
        }
      }
    }

    final reliability = ((recentInteractions / docs.length) * 100).round().clamp(0, 100);
    final engagement = ((streakTotal / docs.length) * 10).round().clamp(0, 100);
    final impact = (100 - (riskTotal / docs.length)).round().clamp(0, 100);
    final overall = ((reliability + engagement + impact) / 3).round().clamp(0, 100);

    return {
      'reliability': reliability,
      'engagement': engagement,
      'impact': impact,
      'overall': overall,
    };
  }

  Future<void> _logInteraction(String mentorshipId) async {
    await widget.service.logMentorInteraction(mentorshipId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interaction logged.'), backgroundColor: Color(0xFF00C09E)),
    );
  }

  Future<void> _recordIntervention(String mentorshipId, String action) async {
    await widget.service.recordIntervention(
      mentorshipId: mentorshipId,
      action: action,
      note: 'Auto logged from mentor dashboard.',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action sent.'), backgroundColor: const Color(0xFF00C09E)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mentorId = widget.service.currentUserId;
    if (mentorId == null) {
      return const Center(child: Text('Sign in to mentor.', style: TextStyle(color: Colors.white54)));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.service.watchMentorshipsForMentor(mentorId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
        }
        final docs = snapshot.data!.docs;
        final scores = _computeScores(docs);
        final theme = widget.service.focusThemeForMonth(DateTime.now());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _mentorScoreCard(scores),
            const SizedBox(height: 16),
            _focusCard(theme),
            const SizedBox(height: 16),
            Text('Assigned mentees', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              _emptyState()
            else
              Column(
                children: docs.map((doc) => _menteeCard(doc)).toList(),
              ),
          ],
        );
      },
    );
  }

  Widget _mentorScoreCard(Map<String, int> scores) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mentor credibility score', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _scoreItem('Reliability', scores['reliability'] ?? 0),
              _scoreItem('Engagement', scores['engagement'] ?? 0),
              _scoreItem('Impact', scores['impact'] ?? 0),
            ],
          ),
          const SizedBox(height: 10),
          Text('Overall score: ${scores['overall'] ?? 0}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _scoreItem(String label, int value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: value / 100,
            minHeight: 6,
            color: tealAccent,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 4),
          Text('$value%', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _focusCard(String theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mentor operating system', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Focus of the month: $theme', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          const Text('Suggested: schedule weekly check-ins and review goals.',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _menteeCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final menteeId = (data['menteeId'] ?? '').toString();
    final menteeName = (data['menteeName'] ?? 'Student').toString();
    final riskScore = (data['riskScore'] as num?)?.toInt() ?? 0;
    final riskFlags = List<String>.from(data['riskFlags'] ?? []);
    final focusTheme = (data['focusTheme'] ?? widget.service.focusThemeForMonth(DateTime.now())).toString();
    final nextCheckIn = (data['nextCheckInDueAt'] as Timestamp?)?.toDate();
    final lastInteraction = (data['lastInteractionAt'] as Timestamp?)?.toDate();

    final talkingPoints = widget.service.talkingPointsForTheme(focusTheme, riskFlags);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(menteeName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _riskColor(riskScore).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _riskLabel(riskScore),
                  style: TextStyle(color: _riskColor(riskScore), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Next check-in: ${_formatDate(nextCheckIn)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (lastInteraction != null)
            Text('Last interaction: ${_formatDate(lastInteraction)}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 10),
          if (riskFlags.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: riskFlags.map((flag) => _chip(flag.replaceAll('_', ' '), Colors.amberAccent)).toList(),
            ),
            const SizedBox(height: 8),
          ],
          Text('Suggested talking points:', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 6),
          ...talkingPoints.map((point) => Text('- $point', style: const TextStyle(color: Colors.white38, fontSize: 11))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => widget.onMessageUser(menteeId, menteeName),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tealAccent,
                    foregroundColor: backgroundColor,
                  ),
                  child: const Text('Message'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _logInteraction(doc.id),
                child: const Text('Log interaction', style: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                color: cardColor,
                icon: const Icon(Icons.more_horiz, color: Colors.white54),
                onSelected: (action) => _recordIntervention(doc.id, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Nudge mentee', child: Text('Nudge', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'Escalate', child: Text('Escalate', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'Refer support', child: Text('Refer support', style: TextStyle(color: Colors.white))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: const Text(
        'You do not have mentees yet. When students match with you, they will show here with risk flags and talking points.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
