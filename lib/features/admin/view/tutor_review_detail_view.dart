import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/platform_admin_service.dart';
import 'package:seshly/services/tutoring_backend_service.dart';

class TutorReviewDetailView extends StatefulWidget {
  const TutorReviewDetailView({super.key, required this.tutorId});

  final String tutorId;

  @override
  State<TutorReviewDetailView> createState() => _TutorReviewDetailViewState();
}

class _TutorReviewDetailViewState extends State<TutorReviewDetailView> {
  static const Color _background = Color(0xFF0F142B);
  static const Color _card = Color(0xFF1E243A);
  static const Color _accent = Color(0xFF00C09E);

  final TutoringBackendService _backend = TutoringBackendService();
  final PlatformAdminService _adminService = const PlatformAdminService();
  late Future<bool> _adminFuture;
  bool _isSubmitting = false;
  String _payoutStatusDraft = 'pending';

  @override
  void initState() {
    super.initState();
    _adminFuture = _adminService.isCurrentUserPlatformAdmin(forceRefresh: true);
  }

  Future<void> _runAction(
    String successMessage,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    if (_isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final result = await action();
      if (!mounted) {
        return;
      }
      final payoutStatus =
          (result['payoutOnboardingStatus'] ?? _payoutStatusDraft).toString();
      setState(() => _payoutStatusDraft = payoutStatus);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } on TutoringBackendException catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'admin',
        source: 'tutor_review_detail',
      );
      if (!mounted) {
        return;
      }
      AppErrorService.instance.showSnackBar(
        context,
        error.message.isEmpty
            ? 'That admin action could not be completed.'
            : error.message,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<String?> _promptForReason({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _card,
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: _background,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (reason == null || reason.trim().isEmpty) {
      return null;
    }
    return reason.trim();
  }

  String _timestampLabel(dynamic value) {
    if (value is Timestamp) {
      return DateFormat('dd MMM yyyy • HH:mm').format(value.toDate().toLocal());
    }
    return 'Not set';
  }

  List<String> _readList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _mergedData(
    Map<String, dynamic> userData,
    Map<String, dynamic> applicationData,
  ) {
    return {
      ...userData,
      ...applicationData,
      'tutorProfile': userData['tutorProfile'],
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _adminFuture,
      builder: (context, adminSnapshot) {
        if (adminSnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: _background,
            body: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        if (adminSnapshot.data != true) {
          return const Scaffold(
            backgroundColor: _background,
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

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.tutorId)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting &&
                !userSnapshot.hasData) {
              return const Scaffold(
                backgroundColor: _background,
                body: Center(child: CircularProgressIndicator(color: _accent)),
              );
            }

            final userData =
                userSnapshot.data?.data() ?? const <String, dynamic>{};

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('tutor_applications')
                  .doc(widget.tutorId)
                  .snapshots(),
              builder: (context, applicationSnapshot) {
                final applicationData =
                    applicationSnapshot.data?.data() ??
                    const <String, dynamic>{};
                final merged = _mergedData(userData, applicationData);
                final name =
                    (merged['fullName'] ??
                            merged['displayName'] ??
                            widget.tutorId)
                        .toString();
                final tutorProfile =
                    userData['tutorProfile'] as Map<String, dynamic>? ?? {};
                final status =
                    (merged['tutorApplicationStatus'] ??
                            merged['status'] ??
                            'draft')
                        .toString()
                        .toUpperCase();
                final eligibility =
                    (merged['tutoringEligibilityStatus'] ?? 'ineligible')
                        .toString()
                        .toUpperCase();
                final payoutStatus =
                    (merged['payoutOnboardingStatus'] ?? 'not_started')
                        .toString()
                        .toLowerCase();
                if (_payoutStatusDraft != payoutStatus) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _payoutStatusDraft = payoutStatus);
                    }
                  });
                }
                final rejectionReason = (merged['rejectionReason'] ?? '')
                    .toString()
                    .trim();
                final suspensionReason = (merged['suspensionReason'] ?? '')
                    .toString()
                    .trim();

                return Scaffold(
                  backgroundColor: _background,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                status,
                                style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _meta('Eligibility', eligibility),
                              _meta(
                                'Payout onboarding',
                                payoutStatus.toUpperCase(),
                              ),
                              _meta(
                                'Admin approval',
                                merged['adminApproval'] == true
                                    ? 'TRUE'
                                    : 'FALSE',
                              ),
                              _meta(
                                'Approved at',
                                _timestampLabel(merged['adminApprovalAt']),
                              ),
                              _meta(
                                'Approved by',
                                (merged['adminApprovalBy'] ?? 'Not set')
                                    .toString(),
                              ),
                              if (rejectionReason.isNotEmpty)
                                _meta('Rejection reason', rejectionReason),
                              if (suspensionReason.isNotEmpty)
                                _meta('Suspension reason', suspensionReason),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Admin actions',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _actionButton(
                                    label: 'Under review',
                                    onPressed: () => _runAction(
                                      'Tutor moved to review.',
                                      () => _backend.reviewTutorApplication(
                                        tutorId: widget.tutorId,
                                      ),
                                    ),
                                  ),
                                  _actionButton(
                                    label: 'Approve',
                                    primary: true,
                                    onPressed: () => _runAction(
                                      'Tutor approved.',
                                      () => _backend.approveTutorApplication(
                                        tutorId: widget.tutorId,
                                      ),
                                    ),
                                  ),
                                  _actionButton(
                                    label: 'Reject',
                                    onPressed: () async {
                                      final reason = await _promptForReason(
                                        title: 'Reject tutor application',
                                        hint: 'Why was this tutor rejected?',
                                      );
                                      if (reason == null) {
                                        return;
                                      }
                                      await _runAction(
                                        'Tutor rejected.',
                                        () => _backend.rejectTutorApplication(
                                          tutorId: widget.tutorId,
                                          rejectionReason: reason,
                                        ),
                                      );
                                    },
                                  ),
                                  _actionButton(
                                    label: 'Suspend',
                                    onPressed: () async {
                                      final reason = await _promptForReason(
                                        title: 'Suspend tutor',
                                        hint: 'Why is this tutor suspended?',
                                      );
                                      if (reason == null) {
                                        return;
                                      }
                                      await _runAction(
                                        'Tutor suspended.',
                                        () => _backend.suspendTutor(
                                          tutorId: widget.tutorId,
                                          suspensionReason: reason,
                                        ),
                                      );
                                    },
                                  ),
                                  _actionButton(
                                    label: 'Restore',
                                    onPressed: () => _runAction(
                                      'Tutor restored.',
                                      () => _backend.restoreTutor(
                                        tutorId: widget.tutorId,
                                      ),
                                    ),
                                  ),
                                  _actionButton(
                                    label: 'Normalize record',
                                    onPressed: () => _runAction(
                                      'Tutor normalization completed.',
                                      () => _backend.runTutorApprovalBackfill(
                                        tutorId: widget.tutorId,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _payoutStatusDraft,
                                      dropdownColor: _card,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Payout readiness',
                                        labelStyle: TextStyle(
                                          color: Colors.white70,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: Colors.white12,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _accent,
                                          ),
                                        ),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'not_started',
                                          child: Text('NOT STARTED'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'pending',
                                          child: Text('PENDING'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'verified',
                                          child: Text('VERIFIED'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'blocked',
                                          child: Text('BLOCKED'),
                                        ),
                                      ],
                                      onChanged: (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(
                                          () => _payoutStatusDraft = value,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton(
                                    onPressed: _isSubmitting
                                        ? null
                                        : () => _runAction(
                                            'Payout readiness updated.',
                                            () => _backend
                                                .setTutorPayoutReadiness(
                                                  tutorId: widget.tutorId,
                                                  payoutOnboardingStatus:
                                                      _payoutStatusDraft,
                                                ),
                                          ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: _background,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 18,
                                      ),
                                    ),
                                    child: const Text(
                                      'Save',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Application snapshot',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _meta(
                                'Subjects',
                                _readList(merged['mainSubjects'])
                                    .followedBy(
                                      _readList(merged['minorSubjects']),
                                    )
                                    .join(', '),
                              ),
                              _meta(
                                'Base rate',
                                'R${merged['baseRate'] ?? tutorProfile['baseRate'] ?? 0}/min',
                              ),
                              _meta(
                                'Highest level',
                                (merged['highestLevel'] ??
                                        tutorProfile['highestLevel'] ??
                                        'Not set')
                                    .toString(),
                              ),
                              _meta(
                                'Qualification',
                                (merged['qualification'] ??
                                        tutorProfile['qualification'] ??
                                        'Not set')
                                    .toString(),
                              ),
                              _meta(
                                'Institution',
                                (merged['institution'] ??
                                        tutorProfile['institution'] ??
                                        'Not set')
                                    .toString(),
                              ),
                              _meta(
                                'Experience',
                                (merged['yearsExperience'] ??
                                        tutorProfile['yearsExperience'] ??
                                        'Not set')
                                    .toString(),
                              ),
                              _meta(
                                'Languages',
                                _readList(merged['languages']).join(', '),
                              ),
                              _meta(
                                'Location',
                                (merged['location'] ??
                                        tutorProfile['location'] ??
                                        'Not set')
                                    .toString(),
                              ),
                              _meta(
                                'Availability',
                                '${_readList(merged['availabilityDays']).join(', ')} ${merged['availabilityWindow'] ?? ''}'
                                    .trim(),
                              ),
                              _meta(
                                'Tutor type',
                                (merged['tutorType'] ??
                                        tutorProfile['tutorType'] ??
                                        'Individual')
                                    .toString(),
                              ),
                              _meta(
                                'Organization',
                                (merged['organizationName'] ??
                                        tutorProfile['organizationName'] ??
                                        'Not set')
                                    .toString(),
                              ),
                              _meta(
                                'Verification link',
                                (merged['verificationLink'] ??
                                        tutorProfile['verificationLink'] ??
                                        'Not set')
                                    .toString(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Payout profiles',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>
                              >(
                                stream: FirebaseFirestore.instance
                                    .collection('tutor_payout_accounts')
                                    .where('tutorId', isEqualTo: widget.tutorId)
                                    .snapshots(),
                                builder: (context, payoutSnapshot) {
                                  final payoutDocs =
                                      payoutSnapshot.data?.docs ?? const [];
                                  if (payoutDocs.isEmpty) {
                                    return const Text(
                                      'No payout accounts found.',
                                      style: TextStyle(color: Colors.white54),
                                    );
                                  }

                                  return Column(
                                    children: payoutDocs.map((doc) {
                                      final payoutData = doc.data();
                                      final title =
                                          (payoutData['bankName'] ?? 'Bank')
                                              .toString();
                                      final suffix =
                                          (payoutData['maskedAccountNumber'] ??
                                                  'No account number')
                                              .toString();
                                      final status =
                                          (payoutData['status'] ?? 'UNKNOWN')
                                              .toString();
                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.black26,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: Colors.white10,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$suffix • $status',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _meta(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: value.trim().isEmpty ? 'Not set' : value,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    return ElevatedButton(
      onPressed: _isSubmitting ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ? _accent : Colors.white12,
        foregroundColor: primary ? _background : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
