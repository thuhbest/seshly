import 'app_access.dart';
import 'package:seshly/services/tutor_organization_service.dart';

enum AccountType { student, instantTutor, unknown }

class EcosystemRoles {
  const EcosystemRoles({
    required this.student,
    required this.tutor,
    required this.mentor,
    required this.universityPartner,
    required this.organizationMember,
    required this.organizationAdmin,
  });

  final bool student;
  final bool tutor;
  final bool mentor;
  final bool universityPartner;
  final bool organizationMember;
  final bool organizationAdmin;

  factory EcosystemRoles.fromUserData(Map<String, dynamic> data) {
    final raw = data['ecosystemProfile'] as Map<String, dynamic>? ?? {};
    final organization = TutorOrganizationService.membershipFromUserData(data);
    return EcosystemRoles(
      student: raw['student'] == true,
      tutor: raw['tutor'] == true,
      mentor: raw['mentor'] == true,
      universityPartner: raw['universityPartner'] == true,
      organizationMember: organization.isActiveApproved,
      organizationAdmin: organization.isAdmin,
    );
  }
}

class AppIdentity {
  const AppIdentity({
    required this.accountType,
    required this.accessTier,
    required this.roles,
    required this.instantTutorAccessMode,
  });

  final AccountType accountType;
  final AppAccessTier accessTier;
  final EcosystemRoles roles;
  final String instantTutorAccessMode;

  factory AppIdentity.fromUserData(
    Map<String, dynamic> data, {
    required bool isAnonymousAuth,
  }) {
    final String rawType = (data['accountType'] ?? '').toString().toLowerCase();
    final bool instantTutor = isAnonymousAuth;

    final AccountType accountType;
    if (instantTutor) {
      accountType = AccountType.instantTutor;
    } else if (rawType.isEmpty ||
        rawType == 'student' ||
        rawType == 'instant_tutor') {
      accountType = AccountType.student;
    } else {
      accountType = AccountType.unknown;
    }

    return AppIdentity(
      accountType: accountType,
      accessTier: instantTutor
          ? AppAccessTier.instantTutor
          : AppAccessTier.verifiedStudent,
      roles: EcosystemRoles.fromUserData(data),
      instantTutorAccessMode: (data['instantTutorAccessMode'] ?? '').toString(),
    );
  }

  bool get isInstantTutor => accessTier == AppAccessTier.instantTutor;

  bool get isVerifiedStudent => accessTier == AppAccessTier.verifiedStudent;

  bool get isOrganizationMember => roles.organizationMember;

  bool get isOrganizationAdmin => roles.organizationAdmin;

  String get accessTierValue =>
      isInstantTutor ? 'instant_tutor' : 'verified_student';

  String get accountTypeValue {
    switch (accountType) {
      case AccountType.instantTutor:
        return 'instant_tutor';
      case AccountType.student:
        return 'student';
      case AccountType.unknown:
        return 'unknown';
    }
  }
}
