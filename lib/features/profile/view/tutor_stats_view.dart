import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(status),
                      const SizedBox(height: 20),
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
