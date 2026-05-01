import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/services/billing_profile_service.dart';
import 'package:seshly/services/tutor_identity_service.dart';
import 'package:seshly/services/tutor_request_service.dart';
import 'package:seshly/services/tutor_session_service.dart';
import 'package:seshly/theme/seshly_theme.dart';
import 'package:seshly/features/tutors/widgets/gold_tick_badge.dart';
import 'package:seshly/features/tutors/view/tutor_organization_profile_view.dart';
import '../widgets/step_card.dart';
import '../view/recharge_view.dart';

class FindTutorView extends StatefulWidget {
  final String? initialSubject;
  final String? questionText;
  final String? postId;

  const FindTutorView({
    super.key,
    this.initialSubject,
    this.questionText,
    this.postId,
  });

  @override
  State<FindTutorView> createState() => _FindTutorViewState();
}

class _FindTutorViewState extends State<FindTutorView> {
  String? selectedSubject;
  bool showOtherField = false;
  bool showResults = false;
  TutorBookingMode _bookingMode = TutorBookingMode.instant;
  final TextEditingController _otherController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final List<String> subjects = [
    "Mathematics",
    "Physics",
    "Chemistry",
    "Programming",
    "Biology",
    "Statistics",
    "Other",
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSubject?.trim();
    if (initial != null && initial.isNotEmpty) {
      if (subjects.contains(initial)) {
        selectedSubject = initial;
      } else {
        showOtherField = true;
        selectedSubject = initial;
        _otherController.text = initial;
      }
    }
  }

  @override
  void dispose() {
    _otherController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = SeshlyPalette.aqua;
    const Color backgroundColor = SeshlyPalette.background;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              Row(
                children: [
                  // Back button with pressing effect
                  PressableIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Find Tutor",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Card-first matching, instant like a ride",
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  PressableTextButton(
                    text: "Payment",
                    icon: Icons.credit_card_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RechargeView()),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 25),

              _buildPaymentMethodCard(tealAccent),
              const SizedBox(height: 35),
              if ((widget.questionText ?? '').isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Question from your post",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.questionText!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Tutors will see the full question before accepting.",
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              const Text(
                "What subject do you need help with?",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Serif',
                ),
              ),
              const SizedBox(height: 15),

              // --- Subject Grid ---
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: subjects.map((sub) => _subjectChip(sub)).toList(),
              ),
              const SizedBox(height: 20),

              // --- Other Subject Input (Shows only when "Other" is selected) ---
              if (showOtherField)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: tealAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: TextField(
                      controller: _otherController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Color(0xFF00C09E),
                          size: 20,
                        ),
                        hintText: "Type your subject here...",
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        suffixIcon: PressableIconButton(
                          icon: Icons.clear,
                          size: 18,
                          color: Colors.white54,
                          onTap: () {
                            setState(() {
                              _otherController.clear();
                              selectedSubject = null;
                              showOtherField = false;
                            });
                          },
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          selectedSubject = value;
                        } else {
                          selectedSubject = null;
                        }
                        showResults = false;
                      },
                    ),
                  ),
                ),

              if (showOtherField) const SizedBox(height: 20),

              const Text(
                "Topic or chapter (optional)",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: TextField(
                  controller: _topicController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "e.g. Chain Rule, Normal Distribution",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Session start mode",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  PressableChip(
                    label: "Start now",
                    isSelected: _bookingMode == TutorBookingMode.instant,
                    onTap: () =>
                        setState(() => _bookingMode = TutorBookingMode.instant),
                  ),
                  PressableChip(
                    label: "Give tutor 5 min",
                    isSelected: _bookingMode == TutorBookingMode.prep5,
                    onTap: () =>
                        setState(() => _bookingMode = TutorBookingMode.prep5),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Find Button with pressing effect ---
              PressableElevatedButton(
                onPressed: selectedSubject != null
                    ? () {
                        // Handle find tutor action
                        setState(() => showResults = true);
                      }
                    : null,
                icon: Icons.send_outlined,
                label: "Find Tutor Instantly",
              ),
              if (showResults) ...[
                const SizedBox(height: 30),
                const Text(
                  "Available tutors",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Serif',
                  ),
                ),
                const SizedBox(height: 12),
                _buildTutorResults(),
              ],
              const SizedBox(height: 40),

              const Text(
                "How it works",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Serif',
                ),
              ),
              const SizedBox(height: 20),

              // --- Steps ---
              const StepCard(
                number: "1",
                title: "Choose Tutor + Mode",
                desc:
                    "Pick a subject and choose instant start or 5-minute prep",
              ),
              const StepCard(
                number: "2",
                title: "Card Authorization",
                desc:
                    "Seshly authorizes your default card when the tutor accepts and shows the estimated session cap",
              ),
              const StepCard(
                number: "3",
                title: "Live Settlement",
                desc:
                    "After the session, Seshly charges the final amount based on the time used",
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard(Color tealAccent) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildPaymentMethodContent(
        tealAccent,
        'Link a card to book a tutor',
        'Instant Tutor Mode supports a temporary tutor-booking card. Verified students use a default saved card.',
        isInstantTutorMode: true,
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final billingProfile = BillingProfileService.fromUserData(
          data,
          isAnonymousAuth: user.isAnonymous,
        );
        return _buildPaymentMethodContent(
          tealAccent,
          billingProfile.isReady
              ? billingProfile.summary
              : billingProfile.emptyHeadline,
          billingProfile.isReady
              ? (billingProfile.isTemporary
                    ? 'This temporary Instant Tutor Mode card is used only for tutor booking and session charges.'
                    : 'This card is used for tutor booking and final session charges.')
              : (billingProfile.isTemporary
                    ? 'Link a temporary tutor-booking card to request tutors without creating a full student account.'
                    : 'Add a card once to request tutors without preloading a wallet.'),
          isInstantTutorMode: billingProfile.isTemporary,
        );
      },
    );
  }

  Widget _buildPaymentMethodContent(
    Color tealAccent,
    String headline,
    String detail, {
    bool isInstantTutorMode = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool stacked = constraints.maxWidth < 620;
          final action = ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RechargeView()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            child: Text(isInstantTutorMode ? 'Link card' : 'Manage card'),
          );

          final detailsBlock = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInstantTutorMode
                      ? "Temporary tutor-booking card"
                      : "Default payment method",
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.credit_card_outlined,
                      color: tealAccent.withValues(alpha: 0.78),
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    detailsBlock,
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: action),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.credit_card_outlined,
                color: tealAccent.withValues(alpha: 0.78),
                size: 32,
              ),
              const SizedBox(width: 14),
              detailsBlock,
              const SizedBox(width: 14),
              action,
            ],
          );
        },
      ),
    );
  }

  String _formatCurrency(num amount) {
    final bool hasDecimals = (amount * 100).round() % 100 != 0;
    return 'R${amount.toStringAsFixed(hasDecimals ? 2 : 0)}';
  }

  Widget _subjectChip(String label) {
    bool isSelected =
        selectedSubject == label || (label == "Other" && showOtherField);

    return PressableChip(
      label: label,
      isSelected: isSelected,
      onTap: () {
        setState(() {
          if (label == "Other") {
            showOtherField = !showOtherField;
            if (showOtherField) {
              selectedSubject = null;
            } else {
              _otherController.clear();
            }
          } else {
            selectedSubject = label;
            showOtherField = false;
            _otherController.clear();
          }
          showResults = false;
        });
      },
    );
  }

  Widget _buildTutorResults() {
    const Color tealAccent = Color(0xFF00C09E);
    final String subject = (selectedSubject ?? "").trim().toLowerCase();

    return FutureBuilder<List<TutorIdentity>>(
      future: TutorIdentityService.searchTutors(subject: subject, limit: 20),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: tealAccent),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Unable to load tutors right now.",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          );
        }

        final tutors = snapshot.data ?? [];
        final matches = tutors.where((tutor) {
          // Additional client-side filtering if needed
          return tutor.canReceiveRequests && tutor.id.trim().isNotEmpty;
        }).toList();

        if (matches.isEmpty) {
          return Text(
            "No tutors online for that subject yet.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          );
        }

        return Column(
          children: matches.map((tutor) {
            final name = tutor.displayName.isNotEmpty
                ? tutor.displayName
                : "Tutor";
            final tutorSubjects = tutor.allSubjects;
            final pricing = tutor.pricing;
            final bool canRequest =
                tutor.canReceiveRequests && tutor.id.trim().isNotEmpty;
            final Color statusColor =
                tutor.availability == TutorAvailabilityState.accepting
                ? Colors.green
                : tutor.availability == TutorAvailabilityState.afterCurrent
                ? Colors.orangeAccent
                : Colors.white54;
            final String statusLabel = tutor.availabilityLabel;

            return GestureDetector(
              onTap: () => _openTutorProfileSheet(
                tutorId: tutor.id,
                tutorData: const <String, dynamic>{},
                tutor: tutor,
                tutorName: name,
                statusColor: statusColor,
                statusLabel: statusLabel,
                canRequest: canRequest,
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTutorAvatar(
                          tutor: tutor,
                          fallbackName: name,
                          radius: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (tutor.goldTick.badgeVisible) ...[
                                    const SizedBox(width: 6),
                                    const GoldTickBadge(),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tutorSubjects.isNotEmpty
                                    ? tutorSubjects.join(", ")
                                    : "Subjects not set",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tutor.performance.ratingCount > 0
                                    ? '${tutor.performance.ratingLabel} • ${tutor.performance.ratingCountLabel} • ${tutor.performance.qualifyingSessionCount} qualifying sessions'
                                    : '${tutor.performance.ratingLabel} • ${tutor.performance.qualifyingSessionCount} qualifying sessions',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                              if (tutor.organization.isLinkedOrganization) ...[
                                const SizedBox(height: 4),
                                Text(
                                  "Member of ${tutor.organization.name}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 136),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                "You pay ${_formatCurrency(pricing.totalRatePerMinute)}/min",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: tealAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  statusLabel,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canRequest
                            ? () => _createTutorRequest(
                                tutor.id,
                                const <String, dynamic>{},
                                pricing,
                              )
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canRequest
                              ? tealAccent
                              : Colors.white12,
                          foregroundColor: const Color(0xFF0F142B),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          canRequest
                              ? (_bookingMode == TutorBookingMode.instant
                                    ? "Request Instant Session"
                                    : "Request +5 min Prep")
                              : (tutor.availability ==
                                        TutorAvailabilityState.afterCurrent
                                    ? "Tutor unavailable (in session)"
                                    : "Tutor unavailable"),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _createTutorRequest(
    String tutorId,
    Map<String, dynamic> tutorData,
    TutorPricingBreakdown pricing,
  ) async {
    final resolvedTutorId = tutorId.trim();
    if (resolvedTutorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Tutor profile is still syncing. Please try again."),
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to request a tutor.")),
      );
      return;
    }

    final String subject = (selectedSubject ?? "").trim();
    if (subject.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Select a subject first.")));
      return;
    }

    try {
      final resolvedTutorData = await _resolveTutorData(
        resolvedTutorId,
        tutorData,
      );
      if (resolvedTutorData.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Tutor details are unavailable right now. Please try again.",
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      final session = AccessController.session(context);
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      await TutorRequestService().createRequest(
        user: user,
        studentData: userData,
        tutorData: resolvedTutorData,
        tutorId: resolvedTutorId,
        subject: subject,
        topic: _topicController.text.trim(),
        questionText: (widget.questionText ?? '').trim(),
        postId: widget.postId,
        bookingMode: _bookingMode,
        pricing: pricing,
        accessTier: session.identity.accessTierValue,
        accountType: session.identity.accountTypeValue,
      );

      if (!mounted) return;
      final billingProfile = BillingProfileService.fromUserData(
        userData,
        isAnonymousAuth: user.isAnonymous,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Request sent. Seshly has prepared ${billingProfile.summary} for protected tutoring billing and will settle ${_formatCurrency(pricing.totalRatePerMinute)}/min from the live session.",
          ),
        ),
      );
    } on TutorRequestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      if (error.code == 'missing_payment_method') {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RechargeView()),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Could not send request.")));
    }
  }

  Future<Map<String, dynamic>> _resolveTutorData(
    String tutorId,
    Map<String, dynamic> tutorData,
  ) async {
    if (tutorData.isNotEmpty) return tutorData;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(tutorId)
        .get();
    return snap.data() ?? const <String, dynamic>{};
  }

  Future<void> _openTutorProfileSheet({
    required String tutorId,
    required Map<String, dynamic> tutorData,
    required TutorIdentity tutor,
    required String tutorName,
    required Color statusColor,
    required String statusLabel,
    required bool canRequest,
  }) async {
    final pricing = tutor.pricing;
    final String topic = _topicController.text.trim();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E243A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _buildTutorAvatar(
                      tutor: tutor,
                      fallbackName: tutorName,
                      radius: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  tutorName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (tutor.goldTick.badgeVisible) ...[
                                const SizedBox(width: 8),
                                const GoldTickBadge(showLabel: true),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tutor.organization.subtitle,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _profileMetric(
                      'Price',
                      '${_formatCurrency(pricing.totalRatePerMinute)}/min',
                    ),
                    _profileMetric('Rating', tutor.performance.ratingLabel),
                    _profileMetric(
                      'Ratings',
                      tutor.performance.ratingCount.toString(),
                    ),
                    _profileMetric(
                      'Qualifying sessions',
                      tutor.performance.qualifyingSessionCount.toString(),
                    ),
                    _profileMetric(
                      'Learners',
                      '${tutor.performance.learnersHelped}',
                    ),
                    if (tutor.organization.isLinkedOrganization)
                      _profileMetric(
                        'Org rating',
                        tutor.organization.ratingLabel,
                      ),
                  ],
                ),
                if (tutor.organization.isLinkedOrganization) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F142B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tutor.organization.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${tutor.organization.ratingLabel} • ${tutor.organization.memberTutorCount} tutors',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TutorOrganizationProfileView(
                                    organizationId: tutor.organization.id ?? '',
                                  ),
                                ),
                              );
                            },
                            child: const Text('Open organization profile'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (tutor.goldTick.badgeVisible || tutor.goldTick.isEligible)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: SeshlyPalette.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: SeshlyPalette.gold.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      tutor.goldTick.badgeVisible
                          ? 'Gold Tick active • premium verification badge and priority discovery placement.'
                          : '${tutor.goldTick.eligibilityLabel} • ${tutor.goldTick.pathLabel}.',
                      style: const TextStyle(
                        color: SeshlyPalette.gold,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tutor.allSubjects.isNotEmpty
                      ? tutor.allSubjects.join(', ')
                      : 'Tutor subjects not listed yet.',
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
                if (topic.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Current topic: $topic',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canRequest
                        ? () {
                            Navigator.pop(sheetContext);
                            _createTutorRequest(tutorId, tutorData, pricing);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C09E),
                      foregroundColor: const Color(0xFF0F142B),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _bookingMode == TutorBookingMode.instant
                          ? 'Request Instant Session'
                          : 'Request +5 min Prep',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTutorAvatar({
    required TutorIdentity tutor,
    required String fallbackName,
    required double radius,
  }) {
    final imageUrl = tutor.profileImageUrl.trim();
    final initials = _initialsFromName(fallbackName);
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF00C09E).withValues(alpha: 0.16),
      backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      child: imageUrl.isEmpty
          ? Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF00C09E),
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  String _initialsFromName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'T';
    return parts.map((part) => part[0].toUpperCase()).join();
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
}

/// A pressable icon button with scale animation
class PressableIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const PressableIconButton({
    super.key,
    required this.icon,
    this.size = 24,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  State<PressableIconButton> createState() => _PressableIconButtonState();
}

class _PressableIconButtonState extends State<PressableIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.9 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Icon(widget.icon, color: widget.color, size: widget.size),
      ),
    );
  }
}

/// A pressable text button with scale animation
class PressableTextButton extends StatefulWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onTap;

  const PressableTextButton({
    super.key,
    required this.text,
    this.icon,
    required this.onTap,
  });

  @override
  State<PressableTextButton> createState() => _PressableTextButtonState();
}

class _PressableTextButtonState extends State<PressableTextButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.9 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00C09E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.icon != null)
                Icon(widget.icon, color: const Color(0xFF0F142B), size: 16),
              if (widget.icon != null) const SizedBox(width: 4),
              Text(
                widget.text,
                style: const TextStyle(
                  color: Color(0xFF0F142B),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pressable elevated button with scale animation
class PressableElevatedButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const PressableElevatedButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<PressableElevatedButton> createState() =>
      _PressableElevatedButtonState();
}

class _PressableElevatedButtonState extends State<PressableElevatedButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final double scale = _isPressed ? 0.98 : 1.0;
    final bool isDisabled = widget.onPressed == null;

    return GestureDetector(
      onTapDown: (_) {
        if (!isDisabled) setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        if (!isDisabled) setState(() => _isPressed = false);
      },
      onTapCancel: () {
        if (!isDisabled) setState(() => _isPressed = false);
      },
      onTap: !isDisabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 18),
            label: Text(
              widget.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDisabled
                  ? Colors.white.withValues(alpha: 0.05)
                  : tealAccent.withValues(alpha: 0.6),
              foregroundColor: Colors.white.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pressable chip with scale animation
class PressableChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const PressableChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<PressableChip> createState() => _PressableChipState();
}

class _PressableChipState extends State<PressableChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final double scale = _isPressed ? 0.95 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? tealAccent
                : const Color(0xFF1E243A).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected
                  ? tealAccent
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected
                  ? const Color(0xFF0F142B)
                  : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
