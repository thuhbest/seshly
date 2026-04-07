import 'package:flutter/material.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/features/tutors/view/tutor_organization_hub_view.dart';
import 'package:seshly/features/tutors/widgets/gold_tick_badge.dart';
import 'package:seshly/services/tutor_organization_service.dart';

class TutorOrganizationProfileView extends StatelessWidget {
  const TutorOrganizationProfileView({
    super.key,
    required this.organizationId,
    this.showBack = true,
  });

  final String organizationId;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0F142B);
    final orgService = TutorOrganizationService();
    final session = AccessController.session(context);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text(
          'Organization',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<TutorOrganizationAccount?>(
        stream: orgService.streamOrganization(organizationId),
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

          return StreamBuilder<List<TutorOrganizationMember>>(
            stream: orgService.streamMembers(organizationId, activeOnly: true),
            builder: (context, membersSnapshot) {
              final members = membersSnapshot.data ?? const [];
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerCard(
                      context,
                      organization: organization,
                      isAdmin:
                          session.organization.organizationId ==
                              organization.id &&
                          session.organization.isAdmin,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _statCard('Rating', organization.ratingLabel),
                        _statCard(
                          'Members',
                          '${organization.memberTutorCount}',
                        ),
                        _statCard(
                          'Active tutors',
                          '${organization.activeTutorCount}',
                        ),
                        _statCard(
                          'Sessions',
                          '${organization.totalSessionsCompleted}',
                        ),
                        _statCard(
                          'Plan',
                          organization.subscription.isActive
                              ? organization.subscription.planLabel
                              : 'R250/month',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Coverage'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...organization.subjects.map(_chip),
                        ...organization.services.map(_serviceChip),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('Trust'),
                    _trustCard(organization),
                    const SizedBox(height: 24),
                    _sectionTitle('Member Tutors'),
                    const SizedBox(height: 10),
                    if (membersSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        members.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: Color(0xFF00C09E),
                          ),
                        ),
                      )
                    else if (members.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: const Text(
                          'No active tutors are listed yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    else
                      ...members.map(_memberCard),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _headerCard(
    BuildContext context, {
    required TutorOrganizationAccount organization,
    required bool isAdmin,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF133248), Color(0xFF182134)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFF00C09E).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _logoAvatar(organization.logoUrl, organization.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      organization.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      organization.verificationStatus.label,
                      style: const TextStyle(
                        color: Color(0xFF00C09E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      organization.bio.isNotEmpty
                          ? organization.bio
                          : 'Built for premium academic tutoring teams.',
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                    if (organization.website.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        organization.website,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TutorOrganizationHubView(
                        initialOrganizationId: organization.id,
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
                child: const Text(
                  'Open Organization Desk',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _logoAvatar(String logoUrl, String name) {
    final letter = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'O';
    return CircleAvatar(
      radius: 34,
      backgroundColor: const Color(0xFF00C09E).withValues(alpha: 0.14),
      backgroundImage: logoUrl.trim().isNotEmpty ? NetworkImage(logoUrl) : null,
      child: logoUrl.trim().isEmpty
          ? Text(
              letter,
              style: const TextStyle(
                color: Color(0xFF00C09E),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  Widget _trustCard(TutorOrganizationAccount organization) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            organization.goldTickEligible
                ? 'Organization quality threshold met'
                : 'Organization quality threshold still building',
            style: TextStyle(
              color: organization.goldTickEligible
                  ? const Color(0xFF00C09E)
                  : Colors.amberAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            organization.goldTickEligible
                ? 'This organization is above 8/10, so member tutors can qualify through the organization Gold Tick pathway when their own membership state allows it. The organization score is derived from the average of its tutors’ individual average ratings.'
                : 'Gold Tick organization support unlocks once the organization rating rises above 8/10. The organization score is derived from member tutor averages, while every tutor still keeps their own rating, qualifying sessions, and Gold Tick state.',
            style: const TextStyle(color: Colors.white70, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _memberCard(TutorOrganizationMember member) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF00C09E).withValues(alpha: 0.14),
            backgroundImage: member.profilePic.trim().isNotEmpty
                ? NetworkImage(member.profilePic)
                : null,
            child: member.profilePic.trim().isEmpty
                ? Text(
                    member.name.isNotEmpty
                        ? member.name.substring(0, 1).toUpperCase()
                        : 'T',
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (member.goldTickActive) ...[
                      const SizedBox(width: 8),
                      const GoldTickBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  member.titleLabel,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  '${member.ratingLabel} • ${member.qualifyingSessionCount} qualifying sessions • ${member.sessionsCompleted} total sessions',
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      width: 154,
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
              fontSize: 18,
              fontWeight: FontWeight.bold,
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

  Widget _serviceChip(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        value,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
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
}
