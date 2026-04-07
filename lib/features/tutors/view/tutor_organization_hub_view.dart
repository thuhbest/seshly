import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/access/organization_access_policy.dart';
import 'package:seshly/features/tutors/view/tutor_organization_profile_view.dart';
import 'package:seshly/features/tutors/widgets/gold_tick_badge.dart';
import 'package:seshly/services/organization_subscription_service.dart';
import 'package:seshly/services/tutor_organization_service.dart';

class TutorOrganizationHubView extends StatefulWidget {
  const TutorOrganizationHubView({super.key, this.initialOrganizationId});

  final String? initialOrganizationId;

  @override
  State<TutorOrganizationHubView> createState() =>
      _TutorOrganizationHubViewState();
}

class _TutorOrganizationHubViewState extends State<TutorOrganizationHubView> {
  final _service = TutorOrganizationService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _websiteController = TextEditingController();
  final _logoController = TextEditingController();
  final _subjectsController = TextEditingController();
  final _servicesController = TextEditingController();
  final _joinSearchController = TextEditingController();
  final _memberTitleController = TextEditingController();
  final _joinMessageController = TextEditingController();
  final _inviteEmailController = TextEditingController();
  final _inviteTitleController = TextEditingController();
  final _inviteMessageController = TextEditingController();
  final _organizationSubscriptionService = OrganizationSubscriptionService();

  bool _isBusy = false;
  bool _hydratedOrgForm = false;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _websiteController.dispose();
    _logoController.dispose();
    _subjectsController.dispose();
    _servicesController.dispose();
    _joinSearchController.dispose();
    _memberTitleController.dispose();
    _joinMessageController.dispose();
    _inviteEmailController.dispose();
    _inviteTitleController.dispose();
    _inviteMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0F142B);
    final session = AccessController.session(context);
    final access = OrganizationAccessPolicy.evaluate(
      session,
      surface: OrganizationAccessSurface.hub,
    );
    final organizationId =
        widget.initialOrganizationId ?? session.organization.organizationId;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Organization Account',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: !access.allowed
          ? _blockedBody(access)
          : organizationId.isEmpty
          ? _buildOnboarding(context)
          : _buildOrganizationDesk(context, organizationId),
    );
  }

  Widget _blockedBody(OrganizationAccessDecision access) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1E243A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Organization Accounts',
              style: TextStyle(
                color: Color(0xFF00C09E),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              access.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              access.description,
              style: const TextStyle(color: Colors.white60, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboarding(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return user == null
        ? const Center(
            child: Text(
              'Please sign in.',
              style: TextStyle(color: Colors.white54),
            ),
          )
        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              final userData =
                  userSnapshot.data?.data() ?? const <String, dynamic>{};
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heroCard(),
                    const SizedBox(height: 22),
                    _sectionTitle('Create an organization'),
                    const SizedBox(height: 10),
                    _panel(
                      child: Column(
                        children: [
                          _input(_nameController, 'Organization name'),
                          const SizedBox(height: 10),
                          _input(_bioController, 'About / bio', maxLines: 3),
                          const SizedBox(height: 10),
                          _input(_websiteController, 'Website'),
                          const SizedBox(height: 10),
                          _input(_logoController, 'Logo image URL'),
                          const SizedBox(height: 10),
                          _input(
                            _subjectsController,
                            'Subjects covered (comma separated)',
                          ),
                          const SizedBox(height: 10),
                          _input(
                            _servicesController,
                            'Services offered (comma separated)',
                          ),
                          const SizedBox(height: 10),
                          _input(
                            _memberTitleController,
                            'Your title inside the organization',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isBusy
                                  ? null
                                  : () => _createOrganization(
                                      context,
                                      user: user,
                                      userData: userData,
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C09E),
                                foregroundColor: const Color(0xFF0F142B),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                _isBusy
                                    ? 'Creating...'
                                    : 'Create organization account',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    _sectionTitle('Join an existing organization'),
                    const SizedBox(height: 10),
                    _panel(
                      child: Column(
                        children: [
                          _input(_joinSearchController, 'Search organizations'),
                          const SizedBox(height: 10),
                          _input(
                            _joinMessageController,
                            'Short intro for the organization admin',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          StreamBuilder<List<TutorOrganizationAccount>>(
                            stream: _service.streamOrganizations(
                              search: _joinSearchController.text,
                            ),
                            builder: (context, snapshot) {
                              final organizations = snapshot.data ?? const [];
                              if (snapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  organizations.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00C09E),
                                  ),
                                );
                              }
                              if (organizations.isEmpty) {
                                return const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'No organizations found yet.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                );
                              }
                              return Column(
                                children: organizations.take(8).map((org) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF0F142B,
                                      ).withValues(alpha: 0.75),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          org.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${org.ratingLabel} • ${org.memberTutorCount} tutors',
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (org.subjects.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: org.subjects
                                                .take(4)
                                                .map(_chip)
                                                .toList(),
                                          ),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        TutorOrganizationProfileView(
                                                          organizationId:
                                                              org.id,
                                                        ),
                                                  ),
                                                );
                                              },
                                              child: const Text('View profile'),
                                            ),
                                            const Spacer(),
                                            ElevatedButton(
                                              onPressed: _isBusy
                                                  ? null
                                                  : () => _requestJoin(
                                                      context,
                                                      user: user,
                                                      userData: userData,
                                                      orgId: org.id,
                                                    ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(
                                                  0xFF00C09E,
                                                ),
                                                foregroundColor: const Color(
                                                  0xFF0F142B,
                                                ),
                                              ),
                                              child: const Text(
                                                'Request to join',
                                              ),
                                            ),
                                          ],
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
              );
            },
          );
  }

  Widget _buildOrganizationDesk(BuildContext context, String organizationId) {
    final session = AccessController.session(context);
    final isAdmin =
        session.organization.organizationId == organizationId &&
        session.organization.isAdmin;

    return StreamBuilder<TutorOrganizationAccount?>(
      stream: _service.streamOrganization(organizationId),
      builder: (context, orgSnapshot) {
        final organization = orgSnapshot.data;
        if (!orgSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00C09E)),
          );
        }
        if (organization == null) {
          return const Center(
            child: Text(
              'Organization not found.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        _hydrateOrgControllers(organization);

        return StreamBuilder<List<TutorOrganizationMember>>(
          stream: _service.streamMembers(organizationId),
          builder: (context, membersSnapshot) {
            final members = membersSnapshot.data ?? const [];
            final ratedTutors = members.where(
              (member) => member.ratingCount > 0,
            );
            final goldTickTutors = members
                .where((member) => member.goldTickActive)
                .length;
            final averageQualifyingSessions = members.isEmpty
                ? 0
                : members
                          .map((member) => member.qualifyingSessionCount)
                          .reduce((left, right) => left + right) ~/
                      members.length;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _deskHeader(context, organization, isAdmin),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric('Rating', organization.ratingLabel),
                      _metric('Members', '${organization.memberTutorCount}'),
                      _metric('Active', '${organization.activeTutorCount}'),
                      _metric(
                        'Sessions',
                        '${organization.totalSessionsCompleted}',
                      ),
                      _metric('Rated tutors', '${ratedTutors.length}'),
                      _metric('Gold Tick tutors', '$goldTickTutors'),
                      _metric('Avg qualifying', '$averageQualifyingSessions'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSubscriptionCard(
                    context,
                    organization: organization,
                    isAdmin: isAdmin,
                  ),
                  const SizedBox(height: 24),
                  if (isAdmin) ...[
                    _sectionTitle('Organization profile'),
                    const SizedBox(height: 10),
                    _panel(
                      child: Column(
                        children: [
                          _input(_nameController, 'Organization name'),
                          const SizedBox(height: 10),
                          _input(_bioController, 'About / bio', maxLines: 3),
                          const SizedBox(height: 10),
                          _input(_websiteController, 'Website'),
                          const SizedBox(height: 10),
                          _input(_logoController, 'Logo image URL'),
                          const SizedBox(height: 10),
                          _input(
                            _subjectsController,
                            'Subjects covered (comma separated)',
                          ),
                          const SizedBox(height: 10),
                          _input(
                            _servicesController,
                            'Services offered (comma separated)',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isBusy
                                  ? null
                                  : () => _saveOrganizationProfile(
                                      context,
                                      organization.id,
                                    ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00C09E),
                                foregroundColor: const Color(0xFF0F142B),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                _isBusy
                                    ? 'Saving...'
                                    : 'Save organization profile',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Invite tutors'),
                    const SizedBox(height: 10),
                    _buildInviteDesk(
                      context,
                      organizationId: organizationId,
                      adminData: session.userData,
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Pending join requests'),
                    const SizedBox(height: 10),
                    StreamBuilder<List<TutorOrganizationJoinRequest>>(
                      stream: _service.streamJoinRequests(organizationId),
                      builder: (context, requestsSnapshot) {
                        final requests = requestsSnapshot.data ?? const [];
                        if (requests.isEmpty) {
                          return _emptyPanel('No join requests right now.');
                        }
                        return Column(
                          children: requests.map((request) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF1E243A,
                                ).withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.tutorName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    request.memberTitle.isNotEmpty
                                        ? request.memberTitle
                                        : request.requestedRole.label,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (request.message.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      request.message,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isBusy
                                              ? null
                                              : () => _approveJoinRequest(
                                                  context,
                                                  organizationId,
                                                  request.tutorId,
                                                  request.memberTitle,
                                                ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF00C09E,
                                            ),
                                            foregroundColor: const Color(
                                              0xFF0F142B,
                                            ),
                                          ),
                                          child: const Text('Approve'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _isBusy
                                              ? null
                                              : () => _declineJoinRequest(
                                                  context,
                                                  organizationId,
                                                  request.tutorId,
                                                ),
                                          child: const Text('Decline'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Outstanding invites'),
                    const SizedBox(height: 10),
                    StreamBuilder<List<TutorOrganizationInvite>>(
                      stream: _service.streamInvites(organizationId),
                      builder: (context, invitesSnapshot) {
                        final invites = invitesSnapshot.data ?? const [];
                        if (invites.isEmpty) {
                          return _emptyPanel('No outstanding invites yet.');
                        }
                        return Column(
                          children: invites.map((invite) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF1E243A,
                                ).withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    invite.inviteeEmail,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    invite.memberTitle.isNotEmpty
                                        ? invite.memberTitle
                                        : invite.requestedRole.label,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (invite.message.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      invite.message,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _isBusy
                                          ? null
                                          : () => _cancelInvite(
                                              context,
                                              organizationId,
                                              invite.id,
                                            ),
                                      child: const Text(
                                        'Cancel invite',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                  _sectionTitle('Member tutors'),
                  const SizedBox(height: 10),
                  if (members.isEmpty)
                    _emptyPanel('No tutors are linked yet.')
                  else
                    ...members.map(
                      (member) => _memberDeskCard(
                        context,
                        member: member,
                        isAdmin: isAdmin,
                        organizationId: organization.id,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSubscriptionCard(
    BuildContext context, {
    required TutorOrganizationAccount organization,
    required bool isAdmin,
  }) {
    final subscription = organization.subscription;
    final session = AccessController.session(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1C2A47), Color(0xFF171F33)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFF00C09E).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Organization Plan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${subscription.productName} • ${subscription.planLabel}',
            style: const TextStyle(
              color: Color(0xFF00C09E),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subscription.isActive
                ? 'Premium organization controls are active. Branding, analytics, member operations, and future org billing surfaces can live under this account.'
                : 'R250/month, separate from tutor Gold Tick. This is the org-level premium layer for branding, analytics, member management, and future payouts.',
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric('Status', subscription.status.label),
              _metric('Renewal', subscription.renewalLabel),
              _metric(
                'Billing owner',
                subscription.billingOwnerUserId.isNotEmpty
                    ? subscription.billingOwnerUserId
                    : organization.ownerUserId,
              ),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isBusy || subscription.isActive
                    ? null
                    : () => _activateOrganizationPlan(
                        context,
                        organization: organization,
                        adminData: session.userData,
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C09E),
                  foregroundColor: const Color(0xFF0F142B),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  subscription.isActive
                      ? 'Organization Plan Active'
                      : 'Activate Organization Plan • R250/month',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInviteDesk(
    BuildContext context, {
    required String organizationId,
    required Map<String, dynamic> adminData,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    return _panel(
      child: Column(
        children: [
          _input(_inviteEmailController, 'Tutor email'),
          const SizedBox(height: 10),
          _input(_inviteTitleController, 'Title inside the organization'),
          const SizedBox(height: 10),
          _input(_inviteMessageController, 'Short invite message', maxLines: 3),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBusy || user == null
                  ? null
                  : () => _createInvite(
                      context,
                      organizationId: organizationId,
                      admin: user,
                      adminData: adminData,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C09E),
                foregroundColor: const Color(0xFF0F142B),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _isBusy ? 'Sending...' : 'Send invite',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14344A), Color(0xFF191F34)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFF00C09E).withValues(alpha: 0.18),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tutoring Organization Accounts',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Create a branded parent organization, operate with multiple tutors, track organization-level quality, and let students see your team structure without losing individual tutor trust.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _deskHeader(
    BuildContext context,
    TutorOrganizationAccount organization,
    bool isAdmin,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: const Color(
                  0xFF00C09E,
                ).withValues(alpha: 0.14),
                backgroundImage: organization.logoUrl.trim().isNotEmpty
                    ? NetworkImage(organization.logoUrl)
                    : null,
                child: organization.logoUrl.trim().isEmpty
                    ? Text(
                        organization.name.isNotEmpty
                            ? organization.name.substring(0, 1).toUpperCase()
                            : 'O',
                        style: const TextStyle(
                          color: Color(0xFF00C09E),
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      organization.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      organization.ratingLabel,
                      style: const TextStyle(
                        color: Color(0xFF00C09E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            organization.bio.isNotEmpty
                ? organization.bio
                : 'Add a profile story that explains how your tutoring team helps learners.',
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TutorOrganizationProfileView(
                          organizationId: organization.id,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open public profile'),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C09E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Admin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF00C09E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _memberDeskCard(
    BuildContext context, {
    required TutorOrganizationMember member,
    required bool isAdmin,
    required String organizationId,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  member.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (member.goldTickActive) const GoldTickBadge(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${member.titleLabel} • ${member.ratingLabel}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '${member.qualifyingSessionCount} qualifying sessions • ${member.sessionsCompleted} total sessions',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          if (member.subjects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: member.subjects.take(4).map(_chip).toList(),
            ),
          ],
          if (isAdmin && member.role != OrganizationRole.owner) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isBusy
                      ? null
                      : () =>
                            _toggleMemberRole(context, organizationId, member),
                  child: Text(
                    member.role == OrganizationRole.admin
                        ? 'Set as member'
                        : 'Promote to admin',
                  ),
                ),
                OutlinedButton(
                  onPressed: _isBusy
                      ? null
                      : () => _toggleMemberActivity(
                          context,
                          organizationId,
                          member,
                        ),
                  child: Text(
                    member.isActiveApproved ? 'Set inactive' : 'Set active',
                  ),
                ),
                TextButton(
                  onPressed: _isBusy
                      ? null
                      : () => _removeMember(
                          context,
                          organizationId,
                          member.userId,
                        ),
                  child: const Text(
                    'Remove member',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _activateOrganizationPlan(
    BuildContext context, {
    required TutorOrganizationAccount organization,
    required Map<String, dynamic> adminData,
  }) async {
    setState(() => _isBusy = true);
    try {
      final admin = FirebaseAuth.instance.currentUser;
      if (admin == null) return;
      await _organizationSubscriptionService.activateSubscription(
        adminUser: admin,
        adminUserData: adminData,
        organization: organization,
      );
      _showSnack('Organization plan activated.');
    } on OrganizationSubscriptionException catch (error) {
      _showSnack(error.message);
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _createInvite(
    BuildContext context, {
    required String organizationId,
    required User admin,
    required Map<String, dynamic> adminData,
  }) async {
    setState(() => _isBusy = true);
    try {
      await _service.createInvite(
        orgId: organizationId,
        admin: admin,
        adminData: adminData,
        inviteeEmail: _inviteEmailController.text,
        memberTitle: _inviteTitleController.text,
        message: _inviteMessageController.text,
      );
      _inviteEmailController.clear();
      _inviteTitleController.clear();
      _inviteMessageController.clear();
      _showSnack('Invite sent.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _cancelInvite(
    BuildContext context,
    String organizationId,
    String inviteId,
  ) async {
    setState(() => _isBusy = true);
    try {
      await _service.cancelInvite(orgId: organizationId, inviteId: inviteId);
      _showSnack('Invite cancelled.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _toggleMemberRole(
    BuildContext context,
    String organizationId,
    TutorOrganizationMember member,
  ) async {
    setState(() => _isBusy = true);
    try {
      await _service.updateMemberRole(
        orgId: organizationId,
        tutorId: member.userId,
        role: member.role == OrganizationRole.admin
            ? OrganizationRole.member
            : OrganizationRole.admin,
      );
      _showSnack('Member role updated.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _toggleMemberActivity(
    BuildContext context,
    String organizationId,
    TutorOrganizationMember member,
  ) async {
    setState(() => _isBusy = true);
    try {
      await _service.updateMemberActivity(
        orgId: organizationId,
        tutorId: member.userId,
        active: !member.isActiveApproved,
      );
      _showSnack('Member activity updated.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _createOrganization(
    BuildContext context, {
    required User user,
    required Map<String, dynamic> userData,
  }) async {
    setState(() => _isBusy = true);
    try {
      final orgId = await _service.createOrganization(
        owner: user,
        ownerData: userData,
        name: _nameController.text,
        bio: _bioController.text,
        website: _websiteController.text,
        logoUrl: _logoController.text,
        subjects: _splitCsv(_subjectsController.text),
        services: _splitCsv(_servicesController.text),
        memberTitle: _memberTitleController.text,
      );
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TutorOrganizationHubView(initialOrganizationId: orgId),
        ),
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _requestJoin(
    BuildContext context, {
    required User user,
    required Map<String, dynamic> userData,
    required String orgId,
  }) async {
    setState(() => _isBusy = true);
    try {
      await _service.submitJoinRequest(
        tutor: user,
        tutorData: userData,
        orgId: orgId,
        memberTitle: _memberTitleController.text,
        message: _joinMessageController.text,
      );
      _showSnack('Join request sent.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _saveOrganizationProfile(
    BuildContext context,
    String organizationId,
  ) async {
    if (!await OrganizationAccessPolicy.guard(
      context,
      surface: OrganizationAccessSurface.admin,
    )) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _service.updateOrganizationProfile(
        orgId: organizationId,
        name: _nameController.text,
        bio: _bioController.text,
        website: _websiteController.text,
        logoUrl: _logoController.text,
        subjects: _splitCsv(_subjectsController.text),
        services: _splitCsv(_servicesController.text),
      );
      _showSnack('Organization profile updated.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _approveJoinRequest(
    BuildContext context,
    String organizationId,
    String tutorId,
    String memberTitle,
  ) async {
    if (!await OrganizationAccessPolicy.guard(
      context,
      surface: OrganizationAccessSurface.admin,
    )) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _service.approveJoinRequest(
        orgId: organizationId,
        tutorId: tutorId,
        memberTitle: memberTitle,
      );
      _showSnack('Tutor approved into organization.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _declineJoinRequest(
    BuildContext context,
    String organizationId,
    String tutorId,
  ) async {
    if (!await OrganizationAccessPolicy.guard(
      context,
      surface: OrganizationAccessSurface.admin,
    )) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _service.declineJoinRequest(
        orgId: organizationId,
        tutorId: tutorId,
      );
      _showSnack('Join request declined.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _removeMember(
    BuildContext context,
    String organizationId,
    String tutorId,
  ) async {
    if (!await OrganizationAccessPolicy.guard(
      context,
      surface: OrganizationAccessSurface.admin,
    )) {
      return;
    }

    setState(() => _isBusy = true);
    try {
      await _service.removeMember(orgId: organizationId, tutorId: tutorId);
      _showSnack('Member removed.');
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _hydrateOrgControllers(TutorOrganizationAccount organization) {
    if (_hydratedOrgForm) return;
    _hydratedOrgForm = true;
    _nameController.text = organization.name;
    _bioController.text = organization.bio;
    _websiteController.text = organization.website;
    _logoController.text = organization.logoUrl;
    _subjectsController.text = organization.subjects.join(', ');
    _servicesController.text = organization.services.join(', ');
  }

  List<String> _splitCsv(String raw) {
    return raw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF0F142B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _emptyPanel(String text) {
    return _panel(
      child: Text(text, style: const TextStyle(color: Colors.white54)),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF00C09E).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF00C09E),
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.replaceFirst('Exception: ', ''))),
    );
  }
}
