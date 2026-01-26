import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/features/calendar/models/calendar_event.dart';

class TutorStatsView extends StatelessWidget {
  const TutorStatsView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    final userId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Tutor Stats", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: userId == null
          ? const Center(child: Text("Please sign in.", style: TextStyle(color: Colors.white54)))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: tealAccent));
                }
                final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final tutorStats = data['tutorStats'] as Map<String, dynamic>? ?? {};
                final tutorProfile = data['tutorProfile'] as Map<String, dynamic>? ?? {};

                final int minutesTutored = (tutorStats['minutesTutored'] as num?)?.toInt() ?? 0;
                final int learnersHelped = (tutorStats['learnersHelped'] as num?)?.toInt() ?? 0;
                final int sessionsCompleted = (tutorStats['sessionsCompleted'] as num?)?.toInt() ?? 0;
                final double ratingAvg = (tutorStats['ratingAvg'] as num?)?.toDouble() ?? 0.0;
                final int ratingCount = (tutorStats['ratingCount'] as num?)?.toInt() ?? 0;
                final int totalEarnings = (tutorStats['totalEarnings'] as num?)?.toInt() ?? 0;

                final List<String> mainSubjects = List<String>.from(tutorProfile['mainSubjects'] ?? []);
                final List<String> minorSubjects = List<String>.from(tutorProfile['minorSubjects'] ?? []);
                final String audience = (tutorProfile['targetAudience'] ?? "Varsity Students").toString();
                final String highestLevel = (tutorProfile['highestLevel'] ?? "Not set").toString();
                final int displayRate = (tutorProfile['displayRate'] as num?)?.toInt() ?? 0;
                final String tutorType = (tutorProfile['tutorType'] ?? "Individual").toString();
                final String status = (data['tutorStatus'] ?? tutorProfile['status'] ?? "pending").toString();
                final bool requestsEnabled = data['tutorRequestsEnabled'] == true;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(status),
                      const SizedBox(height: 20),
                      _buildRequestToggle(
                        context,
                        userId,
                        requestsEnabled,
                      ),
                      const SizedBox(height: 20),
                      _buildRequestsSection(userId),
                      const SizedBox(height: 24),
                      _buildStatsGrid(
                        minutesTutored: minutesTutored,
                        learnersHelped: learnersHelped,
                        sessionsCompleted: sessionsCompleted,
                        ratingAvg: ratingAvg,
                        ratingCount: ratingCount,
                        totalEarnings: totalEarnings,
                      ),
                      const SizedBox(height: 24),
                      Text("Tutor Profile", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow("Tutor type", tutorType),
                            _infoRow("Target audience", audience),
                            _infoRow("Highest level", highestLevel),
                            _infoRow(
                              "Rate",
                              displayRate > 0 ? "R$displayRate / min" : "Not set",
                            ),
                            const SizedBox(height: 10),
                            _tagWrap("Main subjects", mainSubjects),
                            const SizedBox(height: 10),
                            _tagWrap("Minor subjects", minorSubjects),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusCard(String status) {
    const Color cardColor = Color(0xFF1E243A);
    final String label = status.toUpperCase();
    final Color tone = status == 'approved' || status == 'active' ? const Color(0xFF00C09E) : Colors.orangeAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 80)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: tone, size: 20),
          const SizedBox(width: 10),
          Text("Status: $label", style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRequestToggle(BuildContext context, String userId, bool isEnabled) {
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              "Receive tutor requests",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: (value) async {
              await FirebaseFirestore.instance.collection('users').doc(userId).update({
                'tutorRequestsEnabled': value,
                'tutorActiveAt': FieldValue.serverTimestamp(),
              });
            },
            activeThumbColor: tealAccent,
            activeTrackColor: tealAccent.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsSection(String userId) {
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tutor_requests')
          .where('tutorId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: tealAccent));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: const Text("No tutor requests yet.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Tutor requests", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final studentName = (data['studentName'] ?? "Student").toString();
              final subject = (data['subject'] ?? "Subject").toString();
              final topic = (data['topic'] ?? '').toString();
              final questionText = (data['questionText'] ?? '').toString();
              final questionSnippet = (data['questionSnippet'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subject, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    if (topic.isNotEmpty)
                      Text("Topic: $topic", style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 8),
                    Text(
                      questionText.isNotEmpty ? questionText : questionSnippet,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _acceptRequest(context, doc.id, data),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: tealAccent,
                              foregroundColor: const Color(0xFF0F142B),
                            ),
                            child: const Text("Accept"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextButton(
                            onPressed: () => _declineRequest(context, doc.id),
                            child: const Text("Decline", style: TextStyle(color: Colors.white54)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _acceptRequest(BuildContext context, String requestId, Map<String, dynamic> data) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!context.mounted) return;
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (!context.mounted) return;
    if (time == null) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final end = start.add(const Duration(minutes: 60));

    final studentId = (data['studentId'] ?? '').toString();
    final tutorId = (data['tutorId'] ?? '').toString();
    final subject = (data['subject'] ?? 'Tutoring').toString();
    final topic = (data['topic'] ?? '').toString();

    await FirebaseFirestore.instance.collection('tutor_requests').doc(requestId).update({
      'status': 'accepted',
      'scheduledAt': Timestamp.fromDate(start.toUtc()),
      'scheduledEnd': Timestamp.fromDate(end.toUtc()),
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    if (studentId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(studentId).collection('calendarEvents').add({
        'title': topic.isEmpty ? 'Tutoring: $subject' : 'Tutoring: $subject ($topic)',
        'start': Timestamp.fromDate(start.toUtc()),
        'end': Timestamp.fromDate(end.toUtc()),
        'location': 'Seshly Tutoring',
        'type': 'Tutoring',
        'colorHex': EventTypePalette.colorHexForType('Tutoring'),
        'source': 'manual',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (tutorId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(tutorId).collection('calendarEvents').add({
        'title': topic.isEmpty ? 'Tutoring: $subject' : 'Tutoring: $subject ($topic)',
        'start': Timestamp.fromDate(start.toUtc()),
        'end': Timestamp.fromDate(end.toUtc()),
        'location': 'Seshly Tutoring',
        'type': 'Tutoring',
        'colorHex': EventTypePalette.colorHexForType('Tutoring'),
        'source': 'manual',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Session scheduled.")));
  }

  Future<void> _declineRequest(BuildContext context, String requestId) async {
    await FirebaseFirestore.instance.collection('tutor_requests').doc(requestId).update({
      'status': 'declined',
      'declinedAt': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request declined.")));
  }

  Widget _buildStatsGrid({
    required int minutesTutored,
    required int learnersHelped,
    required int sessionsCompleted,
    required double ratingAvg,
    required int ratingCount,
    required int totalEarnings,
  }) {
    const Color tealAccent = Color(0xFF00C09E);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _statTile("Minutes tutored", minutesTutored.toString(), Icons.timer_outlined, tealAccent),
        _statTile("Learners helped", learnersHelped.toString(), Icons.people_outline, Colors.orangeAccent),
        _statTile("Sessions done", sessionsCompleted.toString(), Icons.check_circle_outline, Colors.lightBlueAccent),
        _statTile("Rating", "${ratingAvg.toStringAsFixed(1)} ($ratingCount)", Icons.star_border, Colors.amberAccent),
        _statTile("Total earnings", "R$totalEarnings", Icons.account_balance_wallet_outlined, Colors.purpleAccent),
      ],
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _tagWrap(String label, List<String> values) {
    if (values.isEmpty) {
      return Text("$label: Not set", style: const TextStyle(color: Colors.white38, fontSize: 12));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((value) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(value, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11)),
            );
          }).toList(),
        ),
      ],
    );
  }
}
