import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:seshly/widgets/responsive.dart';

class MentorshipAdminView extends StatelessWidget {
  const MentorshipAdminView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mentorship admin', style: TextStyle(color: Colors.white)),
      ),
      body: ResponsiveCenter(
        maxWidth: 980,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('mentorships')
              .where('status', isEqualTo: 'active')
              .snapshots(),
          builder: (context, mentorshipSnap) {
            if (!mentorshipSnap.hasData) {
              return Center(child: CircularProgressIndicator(color: tealAccent));
            }
            final mentorshipDocs = mentorshipSnap.data!.docs;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('mentorship_profiles').snapshots(),
              builder: (context, profileSnap) {
                final profileDocs = profileSnap.data?.docs ?? [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collectionGroup('checkins')
                      .orderBy('createdAt', descending: true)
                      .limit(500)
                      .snapshots(),
                  builder: (context, checkinSnap) {
                    final checkinDocs = checkinSnap.data?.docs ?? [];

                    final metrics = _computeMentorshipMetrics(mentorshipDocs);
                    final deiMetrics = _computeDeiMetrics(profileDocs);
                    final heatmap = _computeStressHeatmap(checkinDocs);

                    return ListView(
                      children: [
                        _metricRow(
                          [
                            _metricCard('Active mentorships', metrics['total'].toString(), cardColor),
                            _metricCard('Dropout risk index', '${metrics['avgRisk']}%', cardColor),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _metricRow(
                          [
                            _metricCard('High risk cases', metrics['highRisk'].toString(), cardColor),
                            _metricCard('Interventions on time', '${metrics['interventionRate']}%', cardColor),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _metricRow(
                          [
                            _metricCard('First-year survival', '${metrics['firstYearRate']}%', cardColor),
                            _metricCard('Mentor engagement', '${metrics['engagementRate']}%', cardColor),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _sectionTitle('Faculty risk comparison'),
                        const SizedBox(height: 8),
                        if ((metrics['facultyRisk'] as Map).isEmpty)
                          _listRow('No faculty data yet', 'Waiting for mentorship activity', cardColor)
                        else
                          ...metrics['facultyRisk'].entries.map((entry) {
                            return _listRow(
                              entry.key,
                              'Avg risk ${entry.value['avg']}% | ${entry.value['count']} mentorships',
                              cardColor,
                            );
                          }),
                        const SizedBox(height: 20),
                        _sectionTitle('Stress heatmap (last 28 days)'),
                        const SizedBox(height: 8),
                        if (heatmap.isEmpty)
                          _listRow('No check-ins yet', 'Waiting for weekly check-ins', cardColor)
                        else
                          ...heatmap.entries.map((entry) {
                            final data = entry.value;
                            final total = data['total'] as int;
                            final struggling = data['struggling'] as int;
                            final ratio = total == 0 ? 0 : ((struggling / total) * 100).round();
                            return _listRow(
                              entry.key,
                              '$ratio% struggling | $total check-ins',
                              cardColor,
                            );
                          }),
                        const SizedBox(height: 20),
                        _sectionTitle('DEI and access reporting'),
                        const SizedBox(height: 8),
                        _listRow('Opt-in rate', '${deiMetrics['optInRate']}%', cardColor),
                        _listRow('First-gen participation', '${deiMetrics['firstGenRate']}%', cardColor),
                        _listRow('International participation', '${deiMetrics['internationalRate']}%', cardColor),
                        _listRow('Funding distribution', deiMetrics['fundingSummary'], cardColor),
                        const SizedBox(height: 20),
                        _sectionTitle('Early warning triggers'),
                        const SizedBox(height: 8),
                        _listRow('Struggling streaks', metrics['strugglingCount'].toString(), cardColor),
                        _listRow('No mentor contact', metrics['noContactCount'].toString(), cardColor),
                        _listRow('Goal stagnation', metrics['goalStagnation'].toString(), cardColor),
                        _listRow('Missed events', metrics['missedEvents'].toString(), cardColor),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F142B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: const Text(
                            'Privacy note: analytics are anonymized. No names or message content are visible to admins.',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Map<String, dynamic> _computeMentorshipMetrics(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final total = docs.length;
    if (total == 0) {
      return {
        'total': 0,
        'avgRisk': 0,
        'highRisk': 0,
        'interventionRate': 0,
        'firstYearRate': 0,
        'engagementRate': 0,
        'facultyRisk': <String, Map<String, int>>{},
        'strugglingCount': 0,
        'noContactCount': 0,
        'goalStagnation': 0,
        'missedEvents': 0,
      };
    }

    final now = DateTime.now();
    int riskTotal = 0;
    int highRisk = 0;
    int interventionOnTime = 0;
    int engagedCount = 0;
    int firstYearCount = 0;
    int firstYearStable = 0;
    int strugglingCount = 0;
    int noContactCount = 0;
    int goalStagnation = 0;
    int missedEvents = 0;
    final facultyTotals = <String, List<int>>{};

    for (final doc in docs) {
      final data = doc.data();
      final riskScore = (data['riskScore'] as num?)?.toInt() ?? 0;
      final riskFlags = List<String>.from(data['riskFlags'] ?? []);
      final faculty = (data['faculty'] ?? 'Unknown').toString();
      final menteeYear = (data['menteeYearNumber'] as num?)?.toInt() ?? 0;
      final lastInteraction = data['lastInteractionAt'] as Timestamp?;

      riskTotal += riskScore;
      if (riskScore >= 70 || riskFlags.contains('mood_struggling')) {
        highRisk += 1;
      }

      if (lastInteraction != null) {
        final diff = now.difference(lastInteraction.toDate()).inDays;
        if (diff <= 7) {
          interventionOnTime += 1;
          engagedCount += 1;
        }
      }

      if (menteeYear == 1) {
        firstYearCount += 1;
        if (riskScore < 50) {
          firstYearStable += 1;
        }
      }

      if (riskFlags.contains('mood_struggling')) strugglingCount += 1;
      if (riskFlags.contains('no_mentor_contact')) noContactCount += 1;
      if (riskFlags.contains('goal_stagnation')) goalStagnation += 1;
      if (riskFlags.contains('missed_events')) missedEvents += 1;

      facultyTotals.putIfAbsent(faculty, () => []);
      facultyTotals[faculty]!.add(riskScore);
    }

    final avgRisk = (riskTotal / total).round();
    final engagementRate = ((engagedCount / total) * 100).round();
    final interventionRate = ((interventionOnTime / total) * 100).round();
    final firstYearRate = firstYearCount == 0 ? 0 : ((firstYearStable / firstYearCount) * 100).round();

    final facultyRisk = <String, Map<String, int>>{};
    facultyTotals.forEach((faculty, risks) {
      final avg = (risks.reduce((a, b) => a + b) / risks.length).round();
      facultyRisk[faculty] = {'avg': avg, 'count': risks.length};
    });

    final sortedFaculty = facultyRisk.entries.toList()
      ..sort((a, b) => b.value['avg']!.compareTo(a.value['avg']!));

    return {
      'total': total,
      'avgRisk': avgRisk,
      'highRisk': highRisk,
      'interventionRate': interventionRate,
      'firstYearRate': firstYearRate,
      'engagementRate': engagementRate,
      'facultyRisk': Map.fromEntries(sortedFaculty.take(6)),
      'strugglingCount': strugglingCount,
      'noContactCount': noContactCount,
      'goalStagnation': goalStagnation,
      'missedEvents': missedEvents,
    };
  }

  Map<String, dynamic> _computeDeiMetrics(List<QueryDocumentSnapshot<Map<String, dynamic>>> profiles) {
    if (profiles.isEmpty) {
      return {
        'optInRate': 0,
        'firstGenRate': 0,
        'internationalRate': 0,
        'fundingSummary': 'No data',
      };
    }

    int optIn = 0;
    int firstGen = 0;
    int international = 0;
    final fundingCounts = <String, int>{};
    int totalMentees = 0;

    for (final doc in profiles) {
      final data = doc.data();
      if (data['role'] != 'mentee') continue;
      totalMentees += 1;
      if (data['optIn'] == true) optIn += 1;

      final background = data['background'] as Map<String, dynamic>? ?? {};
      if (background['firstGen'] == true) firstGen += 1;
      if (background['international'] == true) international += 1;

      final funding = (background['fundingStatus'] ?? 'Unknown').toString();
      fundingCounts[funding] = (fundingCounts[funding] ?? 0) + 1;
    }

    final optInRate = totalMentees == 0 ? 0 : ((optIn / totalMentees) * 100).round();
    final firstGenRate = totalMentees == 0 ? 0 : ((firstGen / totalMentees) * 100).round();
    final internationalRate = totalMentees == 0 ? 0 : ((international / totalMentees) * 100).round();

    final fundingSummary = fundingCounts.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');

    return {
      'optInRate': optInRate,
      'firstGenRate': firstGenRate,
      'internationalRate': internationalRate,
      'fundingSummary': fundingSummary.isEmpty ? 'No data' : fundingSummary,
    };
  }

  Map<String, Map<String, int>> _computeStressHeatmap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> checkins,
  ) {
    final now = DateTime.now();
    final heatmap = <String, Map<String, int>>{};

    for (final doc in checkins) {
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      if (now.difference(createdAt.toDate()).inDays > 28) continue;

      final faculty = (data['faculty'] ?? 'Unknown').toString();
      final mood = (data['mood'] ?? 'unknown').toString();
      heatmap.putIfAbsent(faculty, () => {'total': 0, 'struggling': 0});
      heatmap[faculty]!['total'] = (heatmap[faculty]!['total'] ?? 0) + 1;
      if (mood == 'struggling') {
        heatmap[faculty]!['struggling'] = (heatmap[faculty]!['struggling'] ?? 0) + 1;
      }
    }

    return heatmap;
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16));
  }

  Widget _metricRow(List<Widget> cards) {
    return Row(
      children: List.generate(cards.length, (index) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == cards.length - 1 ? 0 : 10),
            child: cards[index],
          ),
        );
      }),
    );
  }

  Widget _metricCard(String title, String value, Color cardColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _listRow(String title, String value, Color cardColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white))),
          Text(value, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}
