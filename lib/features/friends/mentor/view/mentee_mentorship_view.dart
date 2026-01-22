import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/mentorship_service.dart';
import '../widgets/goals_card.dart';
import '../widgets/mentor_card.dart';

class MenteeMentorshipView extends StatefulWidget {
  final MentorshipService service;
  final void Function(String userId, String userName) onMessageUser;

  const MenteeMentorshipView({
    super.key,
    required this.service,
    required this.onMessageUser,
  });

  @override
  State<MenteeMentorshipView> createState() => _MenteeMentorshipViewState();
}

class _MenteeMentorshipViewState extends State<MenteeMentorshipView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);
  final Color backgroundColor = const Color(0xFF0F142B);
  int _matchRefresh = 0;

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
    if (score >= 70) return 'Red';
    if (score >= 40) return 'Amber';
    return 'Green';
  }

  Future<void> _submitCheckIn({
    required String mentorshipId,
    required String mood,
  }) async {
    final noteController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cardColor,
          title: const Text('Weekly check-in', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Add a quick note (optional)',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: backgroundColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                foregroundColor: backgroundColor,
              ),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (result != true) {
      return;
    }

    await widget.service.submitCheckIn(
      mentorshipId: mentorshipId,
      userId: widget.service.currentUserId ?? '',
      mood: mood,
      note: noteController.text.trim(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Check-in saved.'), backgroundColor: Color(0xFF00C09E)),
    );
  }

  Future<void> _showAddGoalSheet(String mentorshipId) async {
    final titleController = TextEditingController();
    final dueController = TextEditingController();
    String goalType = 'Faculty benchmark';

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a goal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Goal title',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: backgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: goalType,
                dropdownColor: backgroundColor,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: backgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: const [
                  DropdownMenuItem(value: 'Faculty benchmark', child: Text('Faculty benchmark')),
                  DropdownMenuItem(value: 'Academic milestone', child: Text('Academic milestone')),
                  DropdownMenuItem(value: 'Personal habit', child: Text('Personal habit')),
                ],
                onChanged: (value) => goalType = value ?? goalType,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dueController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Due label (e.g. Mid-term, End of month)',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: backgroundColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tealAccent,
                    foregroundColor: backgroundColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Add goal'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != true) return;
    await widget.service.addGoal(
      mentorshipId: mentorshipId,
      title: titleController.text.trim(),
      type: goalType,
      dueLabel: dueController.text.trim(),
    );
  }

  Future<void> _showUpdateGoalDialog({
    required String mentorshipId,
    required String goalId,
    required int progress,
    required int target,
  }) async {
    double current = progress.toDouble();
    final maxValue = target <= 0 ? 1.0 : target.toDouble();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cardColor,
          title: const Text('Update progress', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: current.clamp(0, maxValue).toDouble(),
                    min: 0,
                    max: maxValue,
                    activeColor: tealAccent,
                    onChanged: (value) => setState(() => current = value),
                  ),
                  Text('${current.round()} / $target', style: const TextStyle(color: Colors.white70)),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: tealAccent, foregroundColor: backgroundColor),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != true) return;
    await widget.service.updateGoalProgress(
      mentorshipId: mentorshipId,
      goalId: goalId,
      progress: current.round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.service.currentUserId;
    if (userId == null) {
      return const Center(child: Text('Sign in to use mentorship.', style: TextStyle(color: Colors.white54)));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.service.watchProfile(userId),
      builder: (context, profileSnap) {
        final profile = profileSnap.data?.data();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.service.watchMentorshipsForUser(userId),
          builder: (context, mentorshipSnap) {
            final mentorshipDoc =
                mentorshipSnap.data?.docs.isNotEmpty == true ? mentorshipSnap.data!.docs.first : null;
            final mentorship = mentorshipDoc?.data();
            final hasMentorship = mentorshipDoc != null;
            final focusTheme = (mentorship?['focusTheme'] ?? widget.service.focusThemeForMonth(DateTime.now())).toString();
            final riskScore = (mentorship?['riskScore'] as num?)?.toInt() ?? 0;
            final riskFlags = List<String>.from(mentorship?['riskFlags'] ?? []);
            final nextCheckIn = (mentorship?['nextCheckInDueAt'] as Timestamp?)?.toDate();
            final checkInStreak = (mentorship?['checkInStreak'] as num?)?.toInt() ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusCard(
                  focusTheme: focusTheme,
                  riskScore: riskScore,
                  checkInStreak: checkInStreak,
                  nextCheckIn: nextCheckIn,
                ),
                const SizedBox(height: 16),
                if (hasMentorship)
                  _assignedMentorSection(
                    mentorship: mentorship ?? {},
                    mentorshipId: mentorshipDoc.id,
                  )
                else
                  _emptyMentorCard(),
                const SizedBox(height: 16),
                _checkInCard(hasMentorship ? mentorshipDoc!.id : null),
                const SizedBox(height: 16),
                if (hasMentorship)
                  _goalsSection(mentorshipDoc!.id)
                else
                  _infoCard(
                    title: 'Set goals once you have a mentor',
                    description: 'Match with a mentor to align goals to faculty milestones and career goals.',
                  ),
                const SizedBox(height: 16),
                _privacyCard(profile),
                const SizedBox(height: 16),
                if (!hasMentorship)
                  _matchesSection(profile)
                else
                  _riskFlagsSection(riskFlags),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statusCard({
    required String focusTheme,
    required int riskScore,
    required int checkInStreak,
    required DateTime? nextCheckIn,
  }) {
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
          const Text('Mentorship status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _statusItem('Mentor health', _riskLabel(riskScore), _riskColor(riskScore)),
              _statusItem('Next check-in', _formatDate(nextCheckIn), Colors.white70),
            ],
          ),
          const SizedBox(height: 8),
          _statusItem('Focus of the month', focusTheme, tealAccent),
          if (checkInStreak > 0) ...[
            const SizedBox(height: 8),
            Text('Check-in streak: $checkInStreak weeks',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _statusItem(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _assignedMentorSection({
    required Map<String, dynamic> mentorship,
    required String mentorshipId,
  }) {
    final mentorId = (mentorship['mentorId'] ?? '').toString();
    final mentorName = (mentorship['mentorName'] ?? 'Mentor').toString();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('mentorship_profiles').doc(mentorId).get(),
      builder: (context, profileSnap) {
        final profile = profileSnap.data?.data() ?? {};
        final availability = List<String>.from(profile['availability'] ?? []).join(', ');
        final focusAreas = List<String>.from(profile['focusAreas'] ?? []);
        final badge = (profile['mentorBadge'] ?? 'Certified Mentor').toString();
        final year = (profile['year'] ?? '').toString();
        final major = (profile['major'] ?? '').toString();

        return MentorCard(
          name: mentorName,
          year: year.isEmpty ? 'Mentor' : year,
          major: major.isEmpty ? 'Mentorship' : major,
          badge: badge,
          availability: availability,
          focusAreas: focusAreas,
          onMessage: () => widget.onMessageUser(mentorId, mentorName),
          onSchedule: () => widget.service.logMentorInteraction(mentorshipId),
        );
      },
    );
  }

  Widget _emptyMentorCard() {
    return _infoCard(
      title: 'No mentor yet',
      description: 'Set up a profile and get matched with a mentor aligned to your faculty, goals, and background.',
    );
  }

  Widget _checkInCard(String? mentorshipId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weekly emotional check-in',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'How are you feeling this week?',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _moodItem(Icons.sentiment_very_dissatisfied, 'Struggling', Colors.redAccent, mentorshipId, 'struggling'),
              _moodItem(Icons.sentiment_neutral, 'Okay', Colors.white54, mentorshipId, 'okay'),
              _moodItem(Icons.sentiment_very_satisfied, 'Good', tealAccent, mentorshipId, 'good'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moodItem(
    IconData icon,
    String label,
    Color color,
    String? mentorshipId,
    String moodKey,
  ) {
    return GestureDetector(
      onTap: mentorshipId == null ? null : () => _submitCheckIn(mentorshipId: mentorshipId, mood: moodKey),
      child: Column(
        children: [
          Icon(icon, color: mentorshipId == null ? Colors.white24 : color),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: mentorshipId == null ? Colors.white24 : Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _goalsSection(String mentorshipId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('mentorships')
          .doc(mentorshipId)
          .collection('goals')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, goalsSnap) {
        final goals = goalsSnap.data?.docs
                .map((doc) => {
                      ...doc.data(),
                      'id': doc.id,
                    })
                .toList() ??
            [];
        return GoalsCard(
          goals: goals,
          onAddGoal: () => _showAddGoalSheet(mentorshipId),
          onUpdateGoal: (goalId, progress, target) => _showUpdateGoalDialog(
            mentorshipId: mentorshipId,
            goalId: goalId,
            progress: progress,
            target: target,
          ),
        );
      },
    );
  }

  Widget _privacyCard(Map<String, dynamic>? profile) {
    final optIn = profile?['optIn'] == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Data privacy mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            optIn
                ? 'You opted into anonymized analytics. Admins see trends only, never messages.'
                : 'Opt in to share anonymous trends that help support students. No message content is visible.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _matchesSection(Map<String, dynamic>? profile) {
    if (profile == null || profile.isEmpty) {
      return _infoCard(
        title: 'Complete your profile',
        description: 'Fill in your faculty, year, and interests to get matched with a mentor.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Smart mentor matches', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => setState(() => _matchRefresh += 1),
                child: const Text('Refresh', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<MentorMatch>>(
            key: ValueKey(_matchRefresh),
            future: widget.service.findMentorMatches(menteeProfile: profile),
            builder: (context, matchesSnap) {
              if (matchesSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
              }
              final matches = matchesSnap.data ?? [];
              if (matches.isEmpty) {
                return const Text('No mentors found. Try broadening your profile details.',
                    style: TextStyle(color: Colors.white54, fontSize: 12));
              }

              return Column(
                children: matches.map((match) => _matchCard(match)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _matchCard(MentorMatch match) {
    final profile = match.profile;
    final name = (profile['displayName'] ?? profile['fullName'] ?? 'Mentor').toString();
    final year = (profile['year'] ?? '').toString();
    final major = (profile['major'] ?? '').toString();
    final badge = (profile['mentorBadge'] ?? 'Mentor').toString();
    final availability = List<String>.from(profile['availability'] ?? []).join(', ');
    final focusAreas = List<String>.from(profile['focusAreas'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tealAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${match.score}% match',
                    style: const TextStyle(color: Color(0xFF00C09E), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [year, major].where((item) => item.isNotEmpty).join(' - ').isEmpty
                ? 'Mentor'
                : [year, major].where((item) => item.isNotEmpty).join(' - '),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(badge, tealAccent),
              ...focusAreas.take(3).map((area) => _chip(area, const Color(0xFF00C09E))),
            ],
          ),
          if (availability.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Availability: $availability', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
          if (match.reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Why: ${match.reasons.take(3).join(', ')}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await widget.service.createMentorship(
                      mentorId: match.mentorId,
                      menteeId: widget.service.currentUserId ?? '',
                      matchScore: match.score,
                      matchReasons: match.reasons,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Mentor matched with $name.'),
                        backgroundColor: const Color(0xFF00C09E),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tealAccent,
                    foregroundColor: backgroundColor,
                  ),
                  child: const Text('Connect'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => widget.onMessageUser(match.mentorId, name),
                child: const Text('Message', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _riskFlagsSection(List<String> riskFlags) {
    if (riskFlags.isEmpty) {
      return _infoCard(
        title: 'Everything looks stable',
        description: 'Keep checking in weekly and update your goals with your mentor.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Early warning signals', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: riskFlags.map((flag) => _chip(flag.replaceAll('_', ' '), Colors.amberAccent)).toList(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your mentor is alerted so you can get support quickly.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({required String title, required String description}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
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
