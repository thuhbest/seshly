import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/access/tutor_access_policy.dart';
import 'package:seshly/features/profile/view/tutor_application_view.dart';
import 'package:seshly/features/tutors/view/tutor_organization_hub_view.dart';
import 'package:seshly/features/tutors/view/tutor_organization_profile_view.dart';
import 'package:seshly/features/tutors/view/recharge_view.dart';
import 'package:seshly/features/tutors/widgets/gold_tick_badge.dart';
import 'package:seshly/services/gold_tick_service.dart';
import 'package:seshly/services/tutor_desk_service.dart';
import 'package:seshly/services/tutor_identity_service.dart';
import 'package:seshly/services/tutor_request_service.dart';
import 'package:seshly/services/tutor_session_service.dart';

class TutorStatsView extends StatelessWidget {
  const TutorStatsView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);
    final session = AccessController.session(context);
    final access = TutorAccessPolicy.evaluate(
      session,
      surface: TutorAccessSurface.desk,
    );

    if (!access.allowed) {
      return TutorAccessGate(
        title: access.title,
        description: access.description,
        primaryLabel: session.identity.isVerifiedStudent
            ? 'Open tutor application'
            : null,
        onPrimaryPressed: session.identity.isVerifiedStudent
            ? () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TutorApplicationView(),
                  ),
                );
              }
            : null,
      );
    }

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
        title: const Text(
          "Tutor Stats",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: userId == null
          ? const Center(
              child: Text(
                "Please sign in.",
                style: TextStyle(color: Colors.white54),
              ),
            )
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: tealAccent),
                  );
                }
                final data =
                    snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final tutor = TutorIdentityService.fromUserData(
                  data,
                  userId: userId,
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatusCard(tutor.statusLabel),
                      const SizedBox(height: 20),
                      _buildRequestToggle(userId, tutor.availability),
                      const SizedBox(height: 20),
                      _buildRequestsSection(userId),
                      const SizedBox(height: 24),
                      _buildStatsGrid(tutor: tutor),
                      const SizedBox(height: 24),
                      _buildGoldTickCard(
                        context,
                        userId: userId,
                        userData: data,
                        tutor: tutor,
                      ),
                      const SizedBox(height: 24),
                      _buildOrganizationAccountCard(context, tutor: tutor),
                      const SizedBox(height: 24),
                      Text(
                        "Tutor Profile",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow(
                              "Tutor type",
                              tutor.organization.tutorType,
                            ),
                            _infoRow("Target audience", tutor.targetAudience),
                            _infoRow("Highest level", tutor.highestLevel),
                            _infoRow(
                              "Rate",
                              tutor.pricing.tutorRatePerMinute > 0
                                  ? "${_money(tutor.pricing.tutorRatePerMinute)} / min"
                                  : "Not set",
                            ),
                            if (tutor.organization.isLinkedOrganization)
                              _infoRow(
                                "Organization",
                                tutor.organization.subtitle,
                              ),
                            if (tutor.organization.isLinkedOrganization)
                              _infoRow(
                                "Org rating",
                                tutor.organization.ratingLabel,
                              ),
                            const SizedBox(height: 10),
                            _tagWrap("Main subjects", tutor.mainSubjects),
                            const SizedBox(height: 10),
                            _tagWrap("Minor subjects", tutor.minorSubjects),
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

  Widget _buildStatusCard(String statusLabel) {
    const Color cardColor = Color(0xFF1E243A);
    final String label = statusLabel.toUpperCase();
    final Color tone = label == 'APPROVED' || label == 'ACTIVE'
        ? const Color(0xFF00C09E)
        : label == 'REJECTED' || label == 'SUSPENDED'
        ? Colors.redAccent
        : Colors.orangeAccent;

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
          Text(
            "Status: $label",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestToggle(
    String userId,
    TutorAvailabilityState availability,
  ) {
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);
    final bool isAccepting = availability == TutorAvailabilityState.accepting;
    final bool isAfterCurrent =
        availability == TutorAvailabilityState.afterCurrent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Tutor availability",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            isAccepting
                ? "You are visible to learners now."
                : isAfterCurrent
                ? "No new requests. You will go fully offline after your current session."
                : "You are offline for new tutor requests.",
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: _availabilityPill(
                  label: "Accepting",
                  selected: isAccepting,
                  color: tealAccent,
                  onTap: () async {
                    await TutorDeskService().updateAvailability(
                      userId: userId,
                      availability: TutorAvailabilityState.accepting,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _availabilityPill(
                  label: "Offline after current",
                  selected: isAfterCurrent,
                  color: Colors.amberAccent,
                  onTap: () async {
                    await TutorDeskService().updateAvailability(
                      userId: userId,
                      availability: TutorAvailabilityState.afterCurrent,
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: _availabilityPill(
                  label: "Offline now",
                  selected: !isAccepting && !isAfterCurrent,
                  color: Colors.orangeAccent,
                  onTap: () async {
                    await TutorDeskService().updateAvailability(
                      userId: userId,
                      availability: TutorAvailabilityState.offline,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _availabilityPill({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? color : Colors.white38,
              size: 15,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
          return const Center(
            child: CircularProgressIndicator(color: tealAccent),
          );
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
            child: const Text(
              "No tutor requests yet.",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tutor requests",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final studentName = (data['studentName'] ?? "Student").toString();
              final subject = (data['subject'] ?? "Subject").toString();
              final topic = (data['topic'] ?? '').toString();
              final questionText = (data['questionText'] ?? '').toString();
              final questionSnippet = (data['questionSnippet'] ?? '')
                  .toString();
              final bookingSummary = _bookingSummary(data);
              final tutorRate = _readRate(data, 'tutorRatePerMinute');
              final platformRate = _readRate(data, 'platformFeePerMinute');
              final totalRate = _readRate(data, 'totalRatePerMinute');
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subject,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    if (topic.isNotEmpty)
                      Text(
                        "Topic: $topic",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      questionText.isNotEmpty ? questionText : questionSnippet,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C09E).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        bookingSummary,
                        style: const TextStyle(
                          color: Color(0xFF00C09E),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (totalRate > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        "Student pays ${_money(totalRate)}/min | You earn ${_money(tutorRate)}/min",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        "Seshly fee: ${_money(platformRate)}/min (${TutorSessionService.platformFeePercent.toStringAsFixed(0)}%)",
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                _acceptRequest(context, doc.id, data),
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
                            child: const Text(
                              "Decline",
                              style: TextStyle(color: Colors.white54),
                            ),
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

  Future<void> _acceptRequest(
    BuildContext context,
    String requestId,
    Map<String, dynamic> data,
  ) async {
    final bookingMode = TutorBookingModeX.fromValue(
      data['bookingMode']?.toString(),
    );
    DateTime start;
    if (data.containsKey('bookingMode')) {
      start = TutorSessionService.computeRequestedStart(
        bookingMode: bookingMode,
      );
    } else {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (!context.mounted) return;
      if (date == null) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (!context.mounted) return;
      if (time == null) return;
      start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }
    await TutorRequestService().acceptRequest(
      requestId: requestId,
      requestData: data,
      startAt: start,
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          data.containsKey('bookingMode')
              ? "Session accepted. ${bookingMode == TutorBookingMode.instant ? "Starting now." : "Start in 5 minutes."}"
              : "Session scheduled.",
        ),
      ),
    );
  }

  Future<void> _declineRequest(BuildContext context, String requestId) async {
    await TutorRequestService().declineRequest(requestId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Request declined.")));
  }

  Widget _buildGoldTickCard(
    BuildContext context, {
    required String userId,
    required Map<String, dynamic> userData,
    required TutorIdentity tutor,
  }) {
    final goldTick = tutor.goldTick;
    final bool canActivate = goldTick.canActivate;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2234), Color(0xFF162232)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GoldTickBadge(showLabel: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Gold Tick',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R30/month • premium badge + discovery priority, gated by real tutor quality.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _profileMetric('Subscription', goldTick.subscriptionLabel),
              _profileMetric('Eligibility', goldTick.eligibilityLabel),
              _profileMetric('Path', goldTick.pathLabel),
              _profileMetric('Renewal', goldTick.periodLabel),
            ],
          ),
          const SizedBox(height: 16),
          _progressTile(
            label: 'Tutor rating',
            valueLabel:
                '${goldTick.ratingLabel} • need above ${GoldTickService.requiredRating.toStringAsFixed(0)}/10',
            progress: goldTick.ratingProgress,
          ),
          const SizedBox(height: 12),
          _progressTile(
            label: 'Qualifying sessions',
            valueLabel:
                '${goldTick.qualifyingSessionLabel} • only sessions longer than 10 min count',
            progress: goldTick.sessionProgress,
          ),
          if (tutor.organization.isLinkedOrganization) ...[
            const SizedBox(height: 12),
            _progressTile(
              label: 'Organization rating',
              valueLabel: goldTick.organizationRatingCount > 0
                  ? '${goldTick.organizationRatingAverage10.toStringAsFixed(1)}/10 • ${goldTick.memberQualificationStatus.replaceAll('_', ' ')}'
                  : 'Organization path unlocks once the org reaches above 8/10',
              progress: goldTick.organizationRatingCount > 0
                  ? (goldTick.organizationRatingAverage10 /
                            GoldTickService.requiredRating)
                        .clamp(0, 1)
                  : 0,
            ),
          ],
          const SizedBox(height: 14),
          Text(
            goldTick.eligibilityReason,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (goldTick.legacyQualificationEstimate) ...[
            const SizedBox(height: 10),
            const Text(
              'Legacy tutor sessions are currently treated as qualified where detailed duration history was not previously stored.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: goldTick.isActive
                  ? null
                  : () => _activateGoldTick(
                      context,
                      userId: userId,
                      userData: userData,
                      canActivate: canActivate,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: canActivate
                    ? Colors.amberAccent
                    : Colors.white10,
                foregroundColor: const Color(0xFF0F142B),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                goldTick.isActive
                    ? 'Gold Tick Active'
                    : canActivate
                    ? 'Activate Gold Tick • R30/month'
                    : 'Keep building toward Gold Tick',
                style: TextStyle(
                  color: canActivate ? const Color(0xFF0F142B) : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationAccountCard(
    BuildContext context, {
    required TutorIdentity tutor,
  }) {
    final hasOrganization = tutor.organization.isLinkedOrganization;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Organization Account',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasOrganization
                ? '${tutor.organization.name} • ${tutor.organization.ratingLabel} • ${tutor.organization.memberTutorCount} tutors'
                : 'Create a parent tutoring organization or request to join one. Organization Accounts are a separate R250/month premium layer above the individual tutor Gold Tick.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (hasOrganization) ...[
            const SizedBox(height: 12),
            Text(
              tutor.organization.subtitle,
              style: const TextStyle(color: Color(0xFF00C09E)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TutorOrganizationHubView(
                          initialOrganizationId: hasOrganization
                              ? tutor.organization.id
                              : null,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C09E),
                    foregroundColor: const Color(0xFF0F142B),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    hasOrganization
                        ? (tutor.organization.isAdmin
                              ? 'Open Organization Desk'
                              : 'Open Organization Account')
                        : 'Create or Join Organization',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (hasOrganization) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TutorOrganizationProfileView(
                            organizationId: tutor.organization.id ?? '',
                          ),
                        ),
                      );
                    },
                    child: const Text('View Public Profile'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressTile({
    required String label,
    required String valueLabel,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            valueLabel,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.amberAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateGoldTick(
    BuildContext context, {
    required String userId,
    required Map<String, dynamic> userData,
    required bool canActivate,
  }) async {
    if (!await TutorAccessPolicy.guard(
      context,
      surface: TutorAccessSurface.goldTick,
    )) {
      return;
    }
    if (!context.mounted) return;

    if (!canActivate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gold Tick stays locked until you meet the quality thresholds.',
          ),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != userId) return;

    try {
      await GoldTickService().activateSubscription(
        user: user,
        userData: userData,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gold Tick activated. Your badge and ranking boost are now live.',
          ),
        ),
      );
    } on GoldTickException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      if (error.code == 'missing_payment_method') {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RechargeView()),
        );
      }
    }
  }

  String _bookingSummary(Map<String, dynamic> data) {
    final mode = data['bookingMode']?.toString();
    final prepMinutes = (data['prepMinutes'] as num?)?.toInt() ?? 5;
    if (mode == 'prep_5' || mode == 'prep5') {
      return "Learner requested start after $prepMinutes min prep";
    }
    if (mode == 'instant') {
      return "Learner requested immediate start";
    }
    return "Legacy request (manual scheduling)";
  }

  double _readRate(Map<String, dynamic> data, String field) {
    final direct = (data[field] as num?)?.toDouble();
    if (direct != null) return direct;
    final pricing = data['pricing'] as Map<String, dynamic>? ?? {};
    return (pricing[field] as num?)?.toDouble() ?? 0;
  }

  String _money(num amount) {
    final hasDecimals = (amount * 100).round() % 100 != 0;
    return "R${amount.toStringAsFixed(hasDecimals ? 2 : 0)}";
  }

  Widget _buildStatsGrid({required TutorIdentity tutor}) {
    const Color tealAccent = Color(0xFF00C09E);

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _statTile(
          "Minutes tutored",
          tutor.performance.minutesTutored.toString(),
          Icons.timer_outlined,
          tealAccent,
        ),
        _statTile(
          "Learners helped",
          tutor.performance.learnersHelped.toString(),
          Icons.people_outline,
          Colors.orangeAccent,
        ),
        _statTile(
          "Sessions done",
          tutor.performance.sessionsCompleted.toString(),
          Icons.check_circle_outline,
          Colors.lightBlueAccent,
        ),
        _statTile(
          "Rating",
          tutor.performance.ratingCount > 0
              ? "${tutor.performance.ratingLabel} ${tutor.performance.ratingCountLabel}"
              : tutor.performance.ratingLabel,
          Icons.star_border,
          Colors.amberAccent,
        ),
        _statTile(
          "Total earnings",
          tutor.performance.earningsLabel,
          Icons.account_balance_wallet_outlined,
          Colors.purpleAccent,
        ),
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
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
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
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagWrap(String label, List<String> values) {
    if (values.isEmpty) {
      return Text(
        "$label: Not set",
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
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
              child: Text(
                value,
                style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
