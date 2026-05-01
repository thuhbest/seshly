import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum OrganizationRole { none, owner, admin, member }

extension OrganizationRoleX on OrganizationRole {
  String get value => name;

  String get label {
    switch (this) {
      case OrganizationRole.owner:
        return 'Owner';
      case OrganizationRole.admin:
        return 'Admin';
      case OrganizationRole.member:
        return 'Member';
      case OrganizationRole.none:
        return 'None';
    }
  }

  static OrganizationRole fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'owner':
        return OrganizationRole.owner;
      case 'admin':
        return OrganizationRole.admin;
      case 'member':
        return OrganizationRole.member;
      default:
        return OrganizationRole.none;
    }
  }
}

enum OrganizationMembershipStatus {
  none,
  pending,
  active,
  inactive,
  removed,
  invited,
}

extension OrganizationMembershipStatusX on OrganizationMembershipStatus {
  String get value => name;

  String get label {
    switch (this) {
      case OrganizationMembershipStatus.pending:
        return 'Pending';
      case OrganizationMembershipStatus.active:
        return 'Active';
      case OrganizationMembershipStatus.inactive:
        return 'Inactive';
      case OrganizationMembershipStatus.removed:
        return 'Removed';
      case OrganizationMembershipStatus.invited:
        return 'Invited';
      case OrganizationMembershipStatus.none:
        return 'None';
    }
  }

  static OrganizationMembershipStatus fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pending':
        return OrganizationMembershipStatus.pending;
      case 'active':
        return OrganizationMembershipStatus.active;
      case 'inactive':
        return OrganizationMembershipStatus.inactive;
      case 'removed':
        return OrganizationMembershipStatus.removed;
      case 'invited':
        return OrganizationMembershipStatus.invited;
      default:
        return OrganizationMembershipStatus.none;
    }
  }
}

enum OrganizationApprovalState { none, pending, approved, rejected }

extension OrganizationApprovalStateX on OrganizationApprovalState {
  String get value => name;

  String get label {
    switch (this) {
      case OrganizationApprovalState.pending:
        return 'Pending';
      case OrganizationApprovalState.approved:
        return 'Approved';
      case OrganizationApprovalState.rejected:
        return 'Rejected';
      case OrganizationApprovalState.none:
        return 'None';
    }
  }

  static OrganizationApprovalState fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pending':
        return OrganizationApprovalState.pending;
      case 'approved':
        return OrganizationApprovalState.approved;
      case 'rejected':
        return OrganizationApprovalState.rejected;
      default:
        return OrganizationApprovalState.none;
    }
  }
}

enum OrganizationVerificationStatus { none, pending, verified, restricted }

extension OrganizationVerificationStatusX on OrganizationVerificationStatus {
  String get value => name;

  String get label {
    switch (this) {
      case OrganizationVerificationStatus.pending:
        return 'Pending verification';
      case OrganizationVerificationStatus.verified:
        return 'Verified';
      case OrganizationVerificationStatus.restricted:
        return 'Restricted';
      case OrganizationVerificationStatus.none:
        return 'Unverified';
    }
  }

  static OrganizationVerificationStatus fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pending':
        return OrganizationVerificationStatus.pending;
      case 'verified':
        return OrganizationVerificationStatus.verified;
      case 'restricted':
        return OrganizationVerificationStatus.restricted;
      default:
        return OrganizationVerificationStatus.none;
    }
  }
}

enum OrganizationAccountSubscriptionStatus {
  none,
  pendingActivation,
  active,
  suspended,
  expired,
}

extension OrganizationAccountSubscriptionStatusX
    on OrganizationAccountSubscriptionStatus {
  String get value => name;

  String get label {
    switch (this) {
      case OrganizationAccountSubscriptionStatus.pendingActivation:
        return 'Pending activation';
      case OrganizationAccountSubscriptionStatus.active:
        return 'Active';
      case OrganizationAccountSubscriptionStatus.suspended:
        return 'Suspended';
      case OrganizationAccountSubscriptionStatus.expired:
        return 'Expired';
      case OrganizationAccountSubscriptionStatus.none:
        return 'Not subscribed';
    }
  }

  static OrganizationAccountSubscriptionStatus fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'pending_activation':
        return OrganizationAccountSubscriptionStatus.pendingActivation;
      case 'active':
        return OrganizationAccountSubscriptionStatus.active;
      case 'suspended':
      case 'suspended_ineligible':
        return OrganizationAccountSubscriptionStatus.suspended;
      case 'expired':
        return OrganizationAccountSubscriptionStatus.expired;
      default:
        return OrganizationAccountSubscriptionStatus.none;
    }
  }
}

class TutorOrganizationMembershipSummary {
  const TutorOrganizationMembershipSummary({
    required this.organizationId,
    required this.organizationName,
    required this.organizationBio,
    required this.organizationLogoUrl,
    required this.organizationWebsite,
    required this.organizationSubjects,
    required this.organizationServices,
    required this.organizationRatingAverage10,
    required this.organizationRatingCount,
    required this.organizationGoldTickEligible,
    required this.organizationSubscriptionStatus,
    required this.organizationPremiumFeaturesEnabled,
    required this.memberTutorCount,
    required this.activeTutorCount,
    required this.role,
    required this.membershipStatus,
    required this.approvalState,
    required this.memberTitle,
    required this.verificationStatus,
  });

  final String organizationId;
  final String organizationName;
  final String organizationBio;
  final String organizationLogoUrl;
  final String organizationWebsite;
  final List<String> organizationSubjects;
  final List<String> organizationServices;
  final double organizationRatingAverage10;
  final int organizationRatingCount;
  final bool organizationGoldTickEligible;
  final OrganizationAccountSubscriptionStatus organizationSubscriptionStatus;
  final bool organizationPremiumFeaturesEnabled;
  final int memberTutorCount;
  final int activeTutorCount;
  final OrganizationRole role;
  final OrganizationMembershipStatus membershipStatus;
  final OrganizationApprovalState approvalState;
  final String memberTitle;
  final OrganizationVerificationStatus verificationStatus;

  static const empty = TutorOrganizationMembershipSummary(
    organizationId: '',
    organizationName: '',
    organizationBio: '',
    organizationLogoUrl: '',
    organizationWebsite: '',
    organizationSubjects: <String>[],
    organizationServices: <String>[],
    organizationRatingAverage10: 0,
    organizationRatingCount: 0,
    organizationGoldTickEligible: false,
    organizationSubscriptionStatus: OrganizationAccountSubscriptionStatus.none,
    organizationPremiumFeaturesEnabled: false,
    memberTutorCount: 0,
    activeTutorCount: 0,
    role: OrganizationRole.none,
    membershipStatus: OrganizationMembershipStatus.none,
    approvalState: OrganizationApprovalState.none,
    memberTitle: '',
    verificationStatus: OrganizationVerificationStatus.none,
  );

  bool get hasOrganization =>
      organizationId.trim().isNotEmpty && organizationName.trim().isNotEmpty;

  bool get isLinked => hasOrganization;

  bool get isActiveApproved =>
      hasOrganization &&
      membershipStatus == OrganizationMembershipStatus.active &&
      approvalState == OrganizationApprovalState.approved;

  bool get isAdmin =>
      isActiveApproved &&
      (role == OrganizationRole.owner || role == OrganizationRole.admin);

  bool get isOwner => isActiveApproved && role == OrganizationRole.owner;

  String get ratingLabel => organizationRatingCount > 0
      ? '${organizationRatingAverage10.toStringAsFixed(1)}/10'
      : 'New organization';

  String get membershipLabel {
    if (!hasOrganization) return 'Independent tutor';
    final parts = <String>[organizationName];
    if (memberTitle.trim().isNotEmpty) {
      parts.add(memberTitle.trim());
    } else if (role != OrganizationRole.none) {
      parts.add(role.label);
    }
    return parts.join(' • ');
  }

  factory TutorOrganizationMembershipSummary.fromUserData(
    Map<String, dynamic> data,
  ) {
    final raw = data['organizationMembership'] as Map<String, dynamic>? ?? {};
    if (raw.isNotEmpty) {
      return TutorOrganizationMembershipSummary(
        organizationId: (raw['organizationId'] ?? '').toString(),
        organizationName: (raw['organizationName'] ?? '').toString(),
        organizationBio: (raw['organizationBio'] ?? '').toString(),
        organizationLogoUrl: (raw['organizationLogoUrl'] ?? '').toString(),
        organizationWebsite: (raw['organizationWebsite'] ?? '').toString(),
        organizationSubjects: _readStringList(raw['organizationSubjects']),
        organizationServices: _readStringList(raw['organizationServices']),
        organizationRatingAverage10:
            (raw['organizationRatingAverage10'] as num?)?.toDouble() ?? 0,
        organizationRatingCount:
            (raw['organizationRatingCount'] as num?)?.toInt() ?? 0,
        organizationGoldTickEligible:
            raw['organizationGoldTickEligible'] == true,
        organizationSubscriptionStatus:
            OrganizationAccountSubscriptionStatusX.fromValue(
              (raw['organizationSubscriptionStatus'] ?? '').toString(),
            ),
        organizationPremiumFeaturesEnabled:
            raw['organizationPremiumFeaturesEnabled'] == true,
        memberTutorCount: (raw['memberTutorCount'] as num?)?.toInt() ?? 0,
        activeTutorCount: (raw['activeTutorCount'] as num?)?.toInt() ?? 0,
        role: OrganizationRoleX.fromValue((raw['role'] ?? '').toString()),
        membershipStatus: OrganizationMembershipStatusX.fromValue(
          (raw['membershipStatus'] ?? '').toString(),
        ),
        approvalState: OrganizationApprovalStateX.fromValue(
          (raw['approvalState'] ?? '').toString(),
        ),
        memberTitle: (raw['memberTitle'] ?? '').toString(),
        verificationStatus: OrganizationVerificationStatusX.fromValue(
          (raw['verificationStatus'] ?? '').toString(),
        ),
      );
    }

    final profile = data['tutorProfile'] as Map<String, dynamic>? ?? {};
    final organizationId =
        (profile['organizationId'] ?? '').toString().trim().isNotEmpty
        ? (profile['organizationId'] ?? '').toString()
        : TutorOrganizationService.deriveOrganizationId(
                tutorType: (profile['tutorType'] ?? 'Individual').toString(),
                organizationName: (profile['organizationName'] ?? '')
                    .toString(),
                website: (profile['organizationWebsite'] ?? '').toString(),
              ) ??
              '';
    final organizationName = (profile['organizationName'] ?? '').toString();
    if (organizationId.isEmpty || organizationName.trim().isEmpty) {
      return empty;
    }

    return TutorOrganizationMembershipSummary(
      organizationId: organizationId,
      organizationName: organizationName,
      organizationBio: '',
      organizationLogoUrl: '',
      organizationWebsite: (profile['organizationWebsite'] ?? '').toString(),
      organizationSubjects: const <String>[],
      organizationServices: const <String>[],
      organizationRatingAverage10: 0,
      organizationRatingCount: 0,
      organizationGoldTickEligible: false,
      organizationSubscriptionStatus:
          OrganizationAccountSubscriptionStatus.none,
      organizationPremiumFeaturesEnabled: false,
      memberTutorCount: 0,
      activeTutorCount: 0,
      role: OrganizationRole.member,
      membershipStatus: OrganizationMembershipStatus.active,
      approvalState: OrganizationApprovalState.approved,
      memberTitle: (profile['organizationRole'] ?? '').toString(),
      verificationStatus: OrganizationVerificationStatus.none,
    );
  }

  static Map<String, dynamic> buildUserMirror({
    required String organizationId,
    required Map<String, dynamic> orgData,
    required OrganizationRole role,
    required OrganizationMembershipStatus membershipStatus,
    required OrganizationApprovalState approvalState,
    required String memberTitle,
  }) {
    return {
      'organizationId': organizationId,
      'organizationName': (orgData['name'] ?? '').toString(),
      'organizationBio': (orgData['bio'] ?? '').toString(),
      'organizationLogoUrl': (orgData['logoUrl'] ?? '').toString(),
      'organizationWebsite': (orgData['website'] ?? '').toString(),
      'organizationSubjects': _readStringList(orgData['subjects']),
      'organizationServices': _readStringList(orgData['services']),
      'organizationRatingAverage10':
          (orgData['ratingAvg10'] as num?)?.toDouble() ?? 0,
      'organizationRatingCount': (orgData['ratingCount'] as num?)?.toInt() ?? 0,
      'organizationGoldTickEligible': orgData['goldTickEligible'] == true,
      'organizationSubscriptionStatus':
          (orgData['subscriptionStatus'] ?? 'none').toString(),
      'organizationPremiumFeaturesEnabled':
          orgData['premiumFeaturesEnabled'] == true,
      'memberTutorCount': (orgData['memberTutorCount'] as num?)?.toInt() ?? 0,
      'activeTutorCount': (orgData['activeTutorCount'] as num?)?.toInt() ?? 0,
      'role': role.value,
      'membershipStatus': membershipStatus.value,
      'approvalState': approvalState.value,
      'memberTitle': memberTitle,
      'verificationStatus': (orgData['verificationStatus'] ?? 'none')
          .toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }
}

class TutorOrganizationAccount {
  const TutorOrganizationAccount({
    required this.id,
    required this.name,
    required this.bio,
    required this.logoUrl,
    required this.website,
    required this.subjects,
    required this.services,
    required this.ratingAverage10,
    required this.ratingCount,
    required this.goldTickEligible,
    required this.memberTutorCount,
    required this.activeTutorCount,
    required this.totalSessionsCompleted,
    required this.totalMinutesTutored,
    required this.verificationStatus,
    required this.ownerUserId,
    required this.adminUserIds,
    required this.subscription,
  });

  final String id;
  final String name;
  final String bio;
  final String logoUrl;
  final String website;
  final List<String> subjects;
  final List<String> services;
  final double ratingAverage10;
  final int ratingCount;
  final bool goldTickEligible;
  final int memberTutorCount;
  final int activeTutorCount;
  final int totalSessionsCompleted;
  final int totalMinutesTutored;
  final OrganizationVerificationStatus verificationStatus;
  final String ownerUserId;
  final List<String> adminUserIds;
  final TutorOrganizationSubscriptionSnapshot subscription;

  bool get hasRating => ratingCount > 0 && ratingAverage10 > 0;

  String get ratingLabel => hasRating
      ? '${ratingAverage10.toStringAsFixed(1)}/10'
      : 'New organization';

  factory TutorOrganizationAccount.fromDoc(DocumentSnapshot doc) {
    final data =
        doc.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
    return TutorOrganizationAccount.fromData(doc.id, data);
  }

  factory TutorOrganizationAccount.fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    return TutorOrganizationAccount(
      id: id,
      name: (data['name'] ?? '').toString(),
      bio: (data['bio'] ?? '').toString(),
      logoUrl: (data['logoUrl'] ?? '').toString(),
      website: (data['website'] ?? '').toString(),
      subjects: TutorOrganizationMembershipSummary._readStringList(
        data['subjects'],
      ),
      services: TutorOrganizationMembershipSummary._readStringList(
        data['services'],
      ),
      ratingAverage10: (data['ratingAvg10'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      goldTickEligible: data['goldTickEligible'] == true,
      memberTutorCount: (data['memberTutorCount'] as num?)?.toInt() ?? 0,
      activeTutorCount: (data['activeTutorCount'] as num?)?.toInt() ?? 0,
      totalSessionsCompleted:
          (data['totalSessionsCompleted'] as num?)?.toInt() ?? 0,
      totalMinutesTutored: (data['totalMinutesTutored'] as num?)?.toInt() ?? 0,
      verificationStatus: OrganizationVerificationStatusX.fromValue(
        (data['verificationStatus'] ?? '').toString(),
      ),
      ownerUserId: (data['ownerUserId'] ?? '').toString(),
      adminUserIds: TutorOrganizationMembershipSummary._readStringList(
        data['adminUserIds'],
      ),
      subscription: TutorOrganizationSubscriptionSnapshot.fromOrgData(data),
    );
  }
}

class TutorOrganizationSubscriptionSnapshot {
  const TutorOrganizationSubscriptionSnapshot({
    required this.productName,
    required this.priceZar,
    required this.currency,
    required this.billingPeriod,
    required this.status,
    required this.paymentMethodSummary,
    required this.billingOwnerUserId,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.premiumFeaturesEnabled,
  });

  final String productName;
  final int priceZar;
  final String currency;
  final String billingPeriod;
  final OrganizationAccountSubscriptionStatus status;
  final String paymentMethodSummary;
  final String billingOwnerUserId;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool premiumFeaturesEnabled;

  bool get isActive => status == OrganizationAccountSubscriptionStatus.active;

  String get planLabel => 'R$priceZar/month';

  String get renewalLabel {
    if (currentPeriodEnd == null) return 'Monthly';
    final end = currentPeriodEnd!;
    return '${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}/${end.year}';
  }

  factory TutorOrganizationSubscriptionSnapshot.fromOrgData(
    Map<String, dynamic> data,
  ) {
    return TutorOrganizationSubscriptionSnapshot(
      productName: (data['subscriptionProductName'] ?? 'Organization Account')
          .toString(),
      priceZar: (data['subscriptionPriceZar'] as num?)?.toInt() ?? 250,
      currency: (data['subscriptionCurrency'] ?? 'ZAR').toString(),
      billingPeriod: (data['subscriptionBillingPeriod'] ?? 'monthly')
          .toString(),
      status: OrganizationAccountSubscriptionStatusX.fromValue(
        (data['subscriptionStatus'] ?? '').toString(),
      ),
      paymentMethodSummary: (data['subscriptionPaymentMethodSummary'] ?? '')
          .toString(),
      billingOwnerUserId: (data['billingOwnerUserId'] ?? '').toString(),
      currentPeriodStart: (data['subscriptionCurrentPeriodStart'] as Timestamp?)
          ?.toDate(),
      currentPeriodEnd: (data['subscriptionCurrentPeriodEnd'] as Timestamp?)
          ?.toDate(),
      premiumFeaturesEnabled: data['premiumFeaturesEnabled'] == true,
    );
  }
}

class TutorOrganizationMember {
  const TutorOrganizationMember({
    required this.userId,
    required this.organizationId,
    required this.organizationName,
    required this.organizationLogoUrl,
    required this.name,
    required this.email,
    required this.profilePic,
    required this.role,
    required this.membershipStatus,
    required this.approvalState,
    required this.memberTitle,
    required this.subjects,
    required this.ratingAverage10,
    required this.ratingCount,
    required this.sessionsCompleted,
    required this.qualifyingSessionCount,
    required this.goldTickActive,
    required this.tutorStatus,
  });

  final String userId;
  final String organizationId;
  final String organizationName;
  final String organizationLogoUrl;
  final String name;
  final String email;
  final String profilePic;
  final OrganizationRole role;
  final OrganizationMembershipStatus membershipStatus;
  final OrganizationApprovalState approvalState;
  final String memberTitle;
  final List<String> subjects;
  final double ratingAverage10;
  final int ratingCount;
  final int sessionsCompleted;
  final int qualifyingSessionCount;
  final bool goldTickActive;
  final String tutorStatus;

  bool get isActiveApproved =>
      membershipStatus == OrganizationMembershipStatus.active &&
      approvalState == OrganizationApprovalState.approved;

  String get ratingLabel => ratingCount > 0
      ? '${ratingAverage10.toStringAsFixed(1)}/10'
      : 'New tutor';

  String get titleLabel =>
      memberTitle.trim().isNotEmpty ? memberTitle.trim() : role.label;

  factory TutorOrganizationMember.fromDoc(DocumentSnapshot doc) {
    final data =
        doc.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
    return TutorOrganizationMember(
      userId: doc.id,
      organizationId: (data['organizationId'] ?? '').toString(),
      organizationName: (data['organizationName'] ?? '').toString(),
      organizationLogoUrl: (data['organizationLogoUrl'] ?? '').toString(),
      name: (data['name'] ?? 'Tutor').toString(),
      email: (data['email'] ?? '').toString(),
      profilePic: (data['profilePic'] ?? '').toString(),
      role: OrganizationRoleX.fromValue((data['role'] ?? '').toString()),
      membershipStatus: OrganizationMembershipStatusX.fromValue(
        (data['status'] ?? '').toString(),
      ),
      approvalState: OrganizationApprovalStateX.fromValue(
        (data['approvalState'] ?? '').toString(),
      ),
      memberTitle: (data['memberTitle'] ?? '').toString(),
      subjects: TutorOrganizationMembershipSummary._readStringList(
        data['subjects'],
      ),
      ratingAverage10: (data['ratingAvg10'] as num?)?.toDouble() ?? 0,
      ratingCount: (data['ratingCount'] as num?)?.toInt() ?? 0,
      sessionsCompleted: (data['sessionsCompleted'] as num?)?.toInt() ?? 0,
      qualifyingSessionCount:
          (data['qualifyingSessionCount'] as num?)?.toInt() ?? 0,
      goldTickActive: data['goldTickActive'] == true,
      tutorStatus: (data['tutorStatus'] ?? '').toString(),
    );
  }
}

class TutorOrganizationJoinRequest {
  const TutorOrganizationJoinRequest({
    required this.tutorId,
    required this.tutorName,
    required this.email,
    required this.profilePic,
    required this.message,
    required this.requestedRole,
    required this.memberTitle,
    required this.subjects,
    required this.createdAt,
  });

  final String tutorId;
  final String tutorName;
  final String email;
  final String profilePic;
  final String message;
  final OrganizationRole requestedRole;
  final String memberTitle;
  final List<String> subjects;
  final DateTime? createdAt;

  factory TutorOrganizationJoinRequest.fromDoc(DocumentSnapshot doc) {
    final data =
        doc.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
    return TutorOrganizationJoinRequest(
      tutorId: doc.id,
      tutorName: (data['tutorName'] ?? 'Tutor').toString(),
      email: (data['email'] ?? '').toString(),
      profilePic: (data['profilePic'] ?? '').toString(),
      message: (data['message'] ?? '').toString(),
      requestedRole: OrganizationRoleX.fromValue(
        (data['requestedRole'] ?? '').toString(),
      ),
      memberTitle: (data['memberTitle'] ?? '').toString(),
      subjects: TutorOrganizationMembershipSummary._readStringList(
        data['subjects'],
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TutorOrganizationInvite {
  const TutorOrganizationInvite({
    required this.id,
    required this.organizationId,
    required this.inviteeEmail,
    required this.inviteeUserId,
    required this.requestedRole,
    required this.memberTitle,
    required this.message,
    required this.status,
    required this.createdByUserId,
    required this.createdByName,
    required this.createdAt,
  });

  final String id;
  final String organizationId;
  final String inviteeEmail;
  final String inviteeUserId;
  final OrganizationRole requestedRole;
  final String memberTitle;
  final String message;
  final String status;
  final String createdByUserId;
  final String createdByName;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory TutorOrganizationInvite.fromDoc(DocumentSnapshot doc) {
    final data =
        doc.data() as Map<String, dynamic>? ?? const <String, dynamic>{};
    return TutorOrganizationInvite(
      id: doc.id,
      organizationId: (data['organizationId'] ?? '').toString(),
      inviteeEmail: (data['inviteeEmail'] ?? '').toString(),
      inviteeUserId: (data['inviteeUserId'] ?? '').toString(),
      requestedRole: OrganizationRoleX.fromValue(
        (data['requestedRole'] ?? '').toString(),
      ),
      memberTitle: (data['memberTitle'] ?? '').toString(),
      message: (data['message'] ?? '').toString(),
      status: (data['status'] ?? 'pending').toString(),
      createdByUserId: (data['createdByUserId'] ?? '').toString(),
      createdByName: (data['createdByName'] ?? '').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TutorOrganizationService {
  TutorOrganizationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String? deriveOrganizationId({
    required String tutorType,
    required String organizationName,
    String website = '',
  }) {
    final normalizedName = organizationName.trim();
    if (tutorType == 'Individual' || normalizedName.isEmpty) return null;

    final domain = _domainFromWebsite(website);
    final seed = domain.isNotEmpty ? domain : normalizedName.toLowerCase();
    final slug = seed
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.isEmpty) return null;
    return 'org_$slug';
  }

  static TutorOrganizationMembershipSummary membershipFromUserData(
    Map<String, dynamic> data,
  ) {
    return TutorOrganizationMembershipSummary.fromUserData(data);
  }

  static String _domainFromWebsite(String website) {
    final raw = website.trim().toLowerCase();
    if (raw.isEmpty) return '';
    final withoutProtocol = raw.replaceFirst(RegExp(r'^https?://'), '');
    return withoutProtocol.split('/').first.replaceAll(RegExp(r'^www\.'), '');
  }

  Stream<TutorOrganizationAccount?> streamOrganization(String orgId) {
    return _db.collection('tutor_organizations').doc(orgId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      return TutorOrganizationAccount.fromDoc(snapshot);
    });
  }

  Stream<List<TutorOrganizationMember>> streamMembers(
    String orgId, {
    bool activeOnly = false,
  }) {
    Query query = _db
        .collection('tutor_organizations')
        .doc(orgId)
        .collection('members');
    if (activeOnly) {
      query = query
          .where('status', isEqualTo: 'active')
          .where('approvalState', isEqualTo: 'approved');
    }

    return query.snapshots().map((snapshot) {
      final members = snapshot.docs
          .map(TutorOrganizationMember.fromDoc)
          .toList();
      members.sort((left, right) {
        if (left.role != right.role) {
          return left.role.index.compareTo(right.role.index);
        }
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
      return members;
    });
  }

  Stream<List<TutorOrganizationJoinRequest>> streamJoinRequests(String orgId) {
    return _db
        .collection('tutor_organizations')
        .doc(orgId)
        .collection('join_requests')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(TutorOrganizationJoinRequest.fromDoc)
              .toList();
        });
  }

  Stream<List<TutorOrganizationInvite>> streamInvites(String orgId) {
    return _db
        .collection('tutor_organizations')
        .doc(orgId)
        .collection('invites')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(TutorOrganizationInvite.fromDoc).toList();
        });
  }

  Stream<List<TutorOrganizationAccount>> streamOrganizations({
    String search = '',
  }) {
    final normalized = search.trim().toLowerCase();
    return _db.collection('tutor_organizations').snapshots().map((snapshot) {
      final organizations =
          snapshot.docs.map(TutorOrganizationAccount.fromDoc).where((org) {
            if (normalized.isEmpty) return true;
            final haystack = [
              org.name,
              ...org.subjects,
              ...org.services,
            ].join(' ').toLowerCase();
            return haystack.contains(normalized);
          }).toList()..sort((left, right) {
            final ratingComparison = right.ratingAverage10.compareTo(
              left.ratingAverage10,
            );
            if (ratingComparison != 0) return ratingComparison;
            return right.memberTutorCount.compareTo(left.memberTutorCount);
          });
      return organizations;
    });
  }

  Future<String> createOrganization({
    required User owner,
    required Map<String, dynamic> ownerData,
    required String name,
    required String bio,
    required String website,
    required String logoUrl,
    required List<String> subjects,
    required List<String> services,
    String memberTitle = 'Founder',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Organization name is required.');
    }
    if (!_isApprovedTutorStatus(ownerData['tutorStatus'])) {
      throw Exception('Only approved tutors can create organization accounts.');
    }

    final existingMembership = membershipFromUserData(ownerData);
    if (existingMembership.isActiveApproved) {
      throw Exception(
        'Leave your current organization before creating a new one.',
      );
    }

    final orgId =
        deriveOrganizationId(
          tutorType: 'Organization',
          organizationName: trimmedName,
          website: website,
        ) ??
        'org_${owner.uid.substring(0, owner.uid.length < 8 ? owner.uid.length : 8)}';

    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    final memberRef = orgRef.collection('members').doc(owner.uid);

    await _db.runTransaction((transaction) async {
      final orgSnap = await transaction.get(orgRef);
      if (orgSnap.exists) {
        throw Exception('An organization with this identity already exists.');
      }

      final now = FieldValue.serverTimestamp();
      final profile = {
        'organizationId': orgId,
        'name': trimmedName,
        'bio': bio.trim(),
        'logoUrl': logoUrl.trim(),
        'website': website.trim(),
        'subjects': subjects,
        'services': services,
        'ratingAvg10': 0.0,
        'ratingCount': 0,
        'ratingTotal10': 0.0,
        'goldTickEligible': false,
        'memberTutorCount': 1,
        'activeTutorCount': 1,
        'totalSessionsCompleted': 0,
        'totalMinutesTutored': 0,
        'ownerUserId': owner.uid,
        'adminUserIds': [owner.uid],
        'billingOwnerUserId': owner.uid,
        'subscriptionProductName': 'Organization Account',
        'subscriptionPriceZar': 250,
        'subscriptionCurrency': 'ZAR',
        'subscriptionBillingPeriod': 'monthly',
        'subscriptionStatus': OrganizationAccountSubscriptionStatus.none.value,
        'premiumFeaturesEnabled': false,
        'verificationStatus': OrganizationVerificationStatus.none.value,
        'createdAt': now,
        'updatedAt': now,
      };

      final memberData = _memberPayload(
        orgId: orgId,
        organizationName: trimmedName,
        organizationLogoUrl: logoUrl.trim(),
        tutorId: owner.uid,
        tutorData: ownerData,
        role: OrganizationRole.owner,
        membershipStatus: OrganizationMembershipStatus.active,
        approvalState: OrganizationApprovalState.approved,
        memberTitle: memberTitle.trim().isEmpty
            ? 'Founder'
            : memberTitle.trim(),
      );

      transaction.set(orgRef, profile);
      transaction.set(memberRef, memberData, SetOptions(merge: true));
    });

    return orgId;
  }

  Future<void> updateOrganizationProfile({
    required String orgId,
    required String name,
    required String bio,
    required String website,
    required String logoUrl,
    required List<String> subjects,
    required List<String> services,
  }) async {
    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    await orgRef.set({
      'name': name.trim(),
      'bio': bio.trim(),
      'website': website.trim(),
      'logoUrl': logoUrl.trim(),
      'subjects': subjects,
      'services': services,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncOrganizationMemberMirrors(orgId);
  }

  Future<void> submitJoinRequest({
    required User tutor,
    required Map<String, dynamic> tutorData,
    required String orgId,
    String memberTitle = '',
    String message = '',
  }) async {
    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    final joinRef = orgRef.collection('join_requests').doc(tutor.uid);
    final membership = membershipFromUserData(tutorData);
    if (membership.isActiveApproved && membership.organizationId != orgId) {
      throw Exception(
        'Leave your current organization before joining a new one.',
      );
    }

    final tutorStatus = (tutorData['tutorStatus'] ?? '')
        .toString()
        .toLowerCase();
    if (tutorStatus != 'approved' && tutorStatus != 'active') {
      throw Exception(
        'Only approved tutors can request to join organizations.',
      );
    }

    final subjects = _readStringList(tutorData['tutorSubjects']);
    final name = (tutorData['fullName'] ?? tutorData['displayName'] ?? 'Tutor')
        .toString();

    await joinRef.set({
      'tutorId': tutor.uid,
      'tutorName': name,
      'email': (tutorData['email'] ?? tutor.email ?? '').toString(),
      'profilePic': (tutorData['profilePic'] ?? '').toString(),
      'message': message.trim(),
      'requestedRole': OrganizationRole.member.value,
      'memberTitle': memberTitle.trim(),
      'subjects': subjects,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> approveJoinRequest({
    required String orgId,
    required String tutorId,
    OrganizationRole role = OrganizationRole.member,
    String memberTitle = '',
  }) async {
    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    final joinRef = orgRef.collection('join_requests').doc(tutorId);
    final memberRef = orgRef.collection('members').doc(tutorId);

    Map<String, dynamic> orgData = const <String, dynamic>{};
    await _db.runTransaction((transaction) async {
      final orgSnap = await transaction.get(orgRef);
      final userRef = _db.collection('users').doc(tutorId);
      final userSnap = await transaction.get(userRef);
      final joinSnap = await transaction.get(joinRef);

      if (!orgSnap.exists) {
        throw Exception('Organization not found.');
      }
      if (!userSnap.exists) {
        throw Exception('Tutor not found.');
      }
      if (!joinSnap.exists) {
        throw Exception('Join request no longer exists.');
      }

      orgData = orgSnap.data() ?? const <String, dynamic>{};
      final userData = userSnap.data() ?? const <String, dynamic>{};
      final joinData = joinSnap.data() ?? const <String, dynamic>{};
      final existingMembership = membershipFromUserData(userData);
      if (existingMembership.isActiveApproved &&
          existingMembership.organizationId != orgId) {
        throw Exception(
          'Tutor already belongs to another active organization.',
        );
      }

      final effectiveTitle = memberTitle.trim().isNotEmpty
          ? memberTitle.trim()
          : (joinData['memberTitle'] ?? '').toString();

      transaction.set(
        memberRef,
        _memberPayload(
          orgId: orgId,
          organizationName: (orgData['name'] ?? '').toString(),
          organizationLogoUrl: (orgData['logoUrl'] ?? '').toString(),
          tutorId: tutorId,
          tutorData: userData,
          role: role,
          membershipStatus: OrganizationMembershipStatus.active,
          approvalState: OrganizationApprovalState.approved,
          memberTitle: effectiveTitle,
        ),
        SetOptions(merge: true),
      );
      transaction.delete(joinRef);
      transaction.set(orgRef, {
        'subjects': FieldValue.arrayUnion(
          _readStringList(userData['tutorSubjects']),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _syncOrganizationMemberMirrors(orgId, orgData: orgData);
  }

  Future<void> declineJoinRequest({
    required String orgId,
    required String tutorId,
  }) {
    return _db
        .collection('tutor_organizations')
        .doc(orgId)
        .collection('join_requests')
        .doc(tutorId)
        .delete();
  }

  Future<void> createInvite({
    required String orgId,
    required User admin,
    required Map<String, dynamic> adminData,
    required String inviteeEmail,
    String inviteeUserId = '',
    OrganizationRole requestedRole = OrganizationRole.member,
    String memberTitle = '',
    String message = '',
  }) async {
    final trimmedEmail = inviteeEmail.trim().toLowerCase();
    if (trimmedEmail.isEmpty || !trimmedEmail.contains('@')) {
      throw Exception('A valid tutor email is required for invites.');
    }
    if (requestedRole == OrganizationRole.none ||
        requestedRole == OrganizationRole.owner) {
      throw Exception('Invites can only grant member or admin access.');
    }

    final inviteRef = _db
        .collection('tutor_organizations')
        .doc(orgId)
        .collection('invites')
        .doc();
    final adminName =
        (adminData['fullName'] ?? adminData['displayName'] ?? 'Admin')
            .toString();

    await inviteRef.set({
      'organizationId': orgId,
      'inviteeEmail': trimmedEmail,
      'inviteeUserId': inviteeUserId.trim(),
      'requestedRole': requestedRole.value,
      'memberTitle': memberTitle.trim(),
      'message': message.trim(),
      'status': 'pending',
      'createdByUserId': admin.uid,
      'createdByName': adminName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> cancelInvite({
    required String orgId,
    required String inviteId,
  }) async {
    await _db
        .collection('tutor_organizations')
        .doc(orgId)
        .collection('invites')
        .doc(inviteId)
        .set({
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> updateMemberRole({
    required String orgId,
    required String tutorId,
    required OrganizationRole role,
  }) async {
    if (role == OrganizationRole.none || role == OrganizationRole.owner) {
      throw Exception('Invalid member role change.');
    }

    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    final memberRef = orgRef.collection('members').doc(tutorId);
    Map<String, dynamic> orgData = const <String, dynamic>{};

    await _db.runTransaction((transaction) async {
      final orgSnap = await transaction.get(orgRef);
      final memberSnap = await transaction.get(memberRef);
      if (!orgSnap.exists || !memberSnap.exists) {
        throw Exception('Organization member not found.');
      }
      orgData = orgSnap.data() ?? const <String, dynamic>{};
      final memberData = memberSnap.data() ?? const <String, dynamic>{};
      final currentRole = OrganizationRoleX.fromValue(
        (memberData['role'] ?? '').toString(),
      );
      if (currentRole == OrganizationRole.owner) {
        throw Exception('The owner role cannot be changed here.');
      }

      transaction.set(memberRef, {
        'role': role.value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _syncOrganizationMemberMirrors(orgId, orgData: orgData);
  }

  Future<void> updateMemberActivity({
    required String orgId,
    required String tutorId,
    required bool active,
  }) async {
    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    final memberRef = orgRef.collection('members').doc(tutorId);
    Map<String, dynamic> orgData = const <String, dynamic>{};

    await _db.runTransaction((transaction) async {
      final orgSnap = await transaction.get(orgRef);
      final memberSnap = await transaction.get(memberRef);
      if (!orgSnap.exists || !memberSnap.exists) {
        throw Exception('Organization member not found.');
      }
      orgData = orgSnap.data() ?? const <String, dynamic>{};
      final memberData = memberSnap.data() ?? const <String, dynamic>{};
      final role = OrganizationRoleX.fromValue(
        (memberData['role'] ?? '').toString(),
      );
      if (role == OrganizationRole.owner && !active) {
        throw Exception('The organization owner cannot be set inactive.');
      }
      final nextStatus = active
          ? OrganizationMembershipStatus.active
          : OrganizationMembershipStatus.inactive;
      final approvalState = active
          ? OrganizationApprovalState.approved
          : OrganizationApprovalState.approved;

      transaction.set(memberRef, {
        'status': nextStatus.value,
        'approvalState': approvalState.value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _syncOrganizationMemberMirrors(orgId, orgData: orgData);
  }

  Future<void> removeMember({
    required String orgId,
    required String tutorId,
  }) async {
    final orgRef = _db.collection('tutor_organizations').doc(orgId);
    final memberRef = orgRef.collection('members').doc(tutorId);

    await _db.runTransaction((transaction) async {
      final memberSnap = await transaction.get(memberRef);
      if (!memberSnap.exists) return;
      final memberData = memberSnap.data() ?? const <String, dynamic>{};
      final role = OrganizationRoleX.fromValue(
        (memberData['role'] ?? '').toString(),
      );
      if (role == OrganizationRole.owner) {
        throw Exception('The organization owner cannot be removed.');
      }

      transaction.set(memberRef, {
        'status': OrganizationMembershipStatus.removed.value,
        'approvalState': OrganizationApprovalState.rejected.value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _syncOrganizationMemberMirrors(orgId);
  }

  Map<String, dynamic> _memberPayload({
    required String orgId,
    required String organizationName,
    required String organizationLogoUrl,
    required String tutorId,
    required Map<String, dynamic> tutorData,
    required OrganizationRole role,
    required OrganizationMembershipStatus membershipStatus,
    required OrganizationApprovalState approvalState,
    required String memberTitle,
  }) {
    final tutorStats = tutorData['tutorStats'] as Map<String, dynamic>? ?? {};
    final subjects = <String>{
      ..._readStringList(
        (tutorData['tutorProfile'] as Map<String, dynamic>? ??
            {})['mainSubjects'],
      ),
      ..._readStringList(tutorData['tutorSubjects']),
    };

    return {
      'organizationId': orgId,
      'organizationName': organizationName,
      'organizationLogoUrl': organizationLogoUrl,
      'tutorId': tutorId,
      'name': (tutorData['fullName'] ?? tutorData['displayName'] ?? 'Tutor')
          .toString(),
      'email': (tutorData['email'] ?? '').toString(),
      'profilePic': (tutorData['profilePic'] ?? '').toString(),
      'role': role.value,
      'status': membershipStatus.value,
      'approvalState': approvalState.value,
      'memberTitle': memberTitle,
      'subjects': subjects.toList(),
      'ratingAvg10': (tutorStats['ratingAvg'] as num?)?.toDouble() ?? 0,
      'ratingCount': (tutorStats['ratingCount'] as num?)?.toInt() ?? 0,
      'sessionsCompleted':
          (tutorStats['sessionsCompleted'] as num?)?.toInt() ?? 0,
      'qualifyingSessionCount':
          (tutorStats['qualifyingSessionCount'] as num?)?.toInt() ??
          (tutorStats['sessionsCompleted'] as num?)?.toInt() ??
          0,
      'goldTickActive':
          ((tutorData['goldTick'] as Map<String, dynamic>? ??
              {})['badgeVisible'] ==
          true),
      'tutorStatus': (tutorData['tutorStatus'] ?? '').toString(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _syncOrganizationMemberMirrors(
    String orgId, {
    Map<String, dynamic>? orgData,
  }) async {
    // Organization membership mirrors are now backend-maintained by the
    // Firestore trigger in functions/src/organizationMembershipMirror.ts.
    return;
  }

  static List<String> _readStringList(dynamic raw) {
    return TutorOrganizationMembershipSummary._readStringList(raw);
  }

  static bool _isApprovedTutorStatus(dynamic rawStatus) {
    final status = (rawStatus ?? '').toString().toLowerCase();
    return status == 'approved' || status == 'active';
  }
}
