import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:seshly/features/admin/view/tutor_review_detail_view.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/platform_admin_service.dart';
import 'package:seshly/services/tutoring_backend_service.dart';

class TutorReviewAdminView extends StatefulWidget {
  const TutorReviewAdminView({super.key});

  @override
  State<TutorReviewAdminView> createState() => _TutorReviewAdminViewState();
}

class _TutorReviewAdminViewState extends State<TutorReviewAdminView> {
  static const Color _background = Color(0xFF0F142B);
  static const Color _card = Color(0xFF1E243A);
  static const Color _accent = Color(0xFF00C09E);

  final TutoringBackendService _backend = TutoringBackendService();
  final PlatformAdminService _adminService = const PlatformAdminService();
  late Future<bool> _adminFuture;

  String _statusFilter = 'all';
  bool _isRunningBackfill = false;
  String? _backfillSummary;

  @override
  void initState() {
    super.initState();
    _adminFuture = _adminService.isCurrentUserPlatformAdmin(forceRefresh: true);
  }

  Future<void> _runBackfill() async {
    if (_isRunningBackfill) {
      return;
    }

    setState(() => _isRunningBackfill = true);
    try {
      final result = await _backend.runTutorApprovalBackfill();
      if (!mounted) {
        return;
      }
      setState(() {
        _backfillSummary =
            'Normalized ${result['normalizedTutorUsers'] ?? 0} tutors, '
            'verified ${result['payoutVerifiedCount'] ?? 0} payouts, '
            'pending ${result['payoutPendingCount'] ?? 0}, '
            'disabled ${result['orphanedSearchProfilesDisabled'] ?? 0} orphan search records.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tutor normalization completed.')),
      );
    } on TutoringBackendException catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'admin',
        source: 'tutor_review_admin',
      );
      if (!mounted) {
        return;
      }
      AppErrorService.instance.showSnackBar(
        context,
        error.message.isEmpty
            ? 'Tutor normalization could not be completed.'
            : error.message,
      );
    } finally {
      if (mounted) {
        setState(() => _isRunningBackfill = false);
      }
    }
  }

  bool _matchesFilter(Map<String, dynamic> data) {
    final status =
        (data['tutorApplicationStatus'] ?? data['status'] ?? 'draft')
            .toString()
            .trim()
            .toLowerCase();
    if (status == 'draft') {
      return false;
    }
    if (_statusFilter == 'all') {
      return true;
    }
    return status == _statusFilter;
  }

  String _statusLabel(Map<String, dynamic> data) {
    return (data['tutorApplicationStatus'] ?? data['status'] ?? 'draft')
        .toString()
        .trim()
        .toUpperCase();
  }

  String _subtitle(Map<String, dynamic> data) {
    final mainSubjects = (data['mainSubjects'] as List?)
            ?.map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList() ??
        const <String>[];
    final rate = (data['baseRate'] ?? '').toString().trim();
    final subjectLabel =
        mainSubjects.isEmpty ? 'No subjects yet' : mainSubjects.join(', ');
    if (rate.isEmpty) {
      return subjectLabel;
    }
    return '$subjectLabel • R$rate/min';
  }

  String _statusMeta(Map<String, dynamic> data) {
    final eligibility =
        (data['tutoringEligibilityStatus'] ?? 'ineligible').toString();
    final payout = (data['payoutOnboardingStatus'] ?? 'not_started').toString();
    final approved = data['adminApproval'] == true ? 'admin approved' : 'awaiting admin';
    return '${eligibility.toUpperCase()} • ${payout.toUpperCase()} • ${approved.toUpperCase()}';
  }

  String _updatedLabel(Map<String, dynamic> data) {
    final raw = data['updatedAt'] ?? data['createdAt'];
    if (raw is Timestamp) {
      return DateFormat('dd MMM yyyy • HH:mm').format(raw.toDate().toLocal());
    }
    return 'No timestamp';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _adminFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: _background,
            body: Center(
              child: CircularProgressIndicator(color: _accent),
            ),
          );
        }

        if (snapshot.data != true) {
          return const _TutorAdminDeniedView();
        }

        return Scaffold(
          backgroundColor: _background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'Tutor Review Admin',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Server-authoritative tutor review',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Approval, eligibility, payout readiness, and tutor search visibility are normalized from backend state only.',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isRunningBackfill ? null : _runBackfill,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: _background,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                _isRunningBackfill
                                    ? 'Normalizing tutors...'
                                    : 'Run Tutor Normalization',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          if (_backfillSummary != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _backfillSummary!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final status in const [
                            'all',
                            'submitted',
                            'under_review',
                            'approved',
                            'rejected',
                            'suspended',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(status.replaceAll('_', ' ').toUpperCase()),
                                selected: _statusFilter == status,
                                onSelected: (_) {
                                  setState(() => _statusFilter = status);
                                },
                                selectedColor: _accent,
                                labelStyle: TextStyle(
                                  color: _statusFilter == status
                                      ? _background
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                                backgroundColor: _card,
                                side: const BorderSide(color: Colors.white10),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('tutor_applications')
                      .limit(150)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _accent),
                      );
                    }

                    final docs = (snapshot.data?.docs ?? const [])
                        .where((doc) => _matchesFilter(doc.data()))
                        .toList()
                      ..sort((left, right) {
                        final leftTs =
                            (left.data()['updatedAt'] ??
                                    left.data()['createdAt']) as Timestamp?;
                        final rightTs =
                            (right.data()['updatedAt'] ??
                                    right.data()['createdAt']) as Timestamp?;
                        return (rightTs?.millisecondsSinceEpoch ?? 0)
                            .compareTo(leftTs?.millisecondsSinceEpoch ?? 0);
                      });

                    if (docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No tutor applications match this filter.',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final name = (data['fullName'] ??
                                data['displayName'] ??
                                docs[index].id)
                            .toString();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TutorReviewDetailView(
                                    tutorId: docs[index].id,
                                  ),
                                ),
                              );
                            },
                            title: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statusLabel(data),
                                    style: const TextStyle(
                                      color: _accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _subtitle(data),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _statusMeta(data),
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _updatedLabel(data),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white54,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TutorAdminDeniedView extends StatelessWidget {
  const _TutorAdminDeniedView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F142B),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Platform admin access is required for tutor review.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
