import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'app_access.dart';
import 'app_identity.dart';
import 'package:seshly/services/tutor_identity_service.dart';
import 'package:seshly/services/tutor_organization_service.dart';

class AppSession {
  const AppSession({
    required this.userId,
    required this.userData,
    required this.identity,
    required this.tutor,
    required this.organization,
    required this.access,
  });

  final String userId;
  final Map<String, dynamic> userData;
  final AppIdentity identity;
  final TutorIdentity tutor;
  final TutorOrganizationMembershipSummary organization;
  final AppAccessProfile access;

  static const EcosystemRoles _verifiedStudentRoles = EcosystemRoles(
    student: true,
    tutor: false,
    mentor: false,
    universityPartner: false,
    organizationMember: false,
    organizationAdmin: false,
  );

  static const EcosystemRoles _instantTutorRoles = EcosystemRoles(
    student: false,
    tutor: false,
    mentor: false,
    universityPartner: false,
    organizationMember: false,
    organizationAdmin: false,
  );

  static const AppIdentity _verifiedStudentIdentity = AppIdentity(
    accountType: AccountType.student,
    accessTier: AppAccessTier.verifiedStudent,
    roles: _verifiedStudentRoles,
    instantTutorAccessMode: '',
  );

  static const AppIdentity _instantTutorIdentity = AppIdentity(
    accountType: AccountType.instantTutor,
    accessTier: AppAccessTier.instantTutor,
    roles: _instantTutorRoles,
    instantTutorAccessMode: '',
  );

  static final AppSession empty = AppSession(
    userId: '',
    userData: const <String, dynamic>{},
    identity: const AppIdentity(
      accountType: AccountType.unknown,
      accessTier: AppAccessTier.instantTutor,
      roles: _instantTutorRoles,
      instantTutorAccessMode: '',
    ),
    tutor: TutorIdentity.empty,
    organization: TutorOrganizationMembershipSummary.empty,
    access: AppAccessProfile.fromIdentity(
      const AppIdentity(
        accountType: AccountType.unknown,
        accessTier: AppAccessTier.instantTutor,
        roles: _instantTutorRoles,
        instantTutorAccessMode: '',
      ),
    ),
  );

  static AppSession fallbackFromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return empty;
    }
    final identity = user.isAnonymous
        ? _instantTutorIdentity
        : _verifiedStudentIdentity;
    return AppSession(
      userId: user.uid,
      userData: const <String, dynamic>{},
      identity: identity,
      tutor: TutorIdentity.empty,
      organization: TutorOrganizationMembershipSummary.empty,
      access: AppAccessProfile.fromIdentity(identity),
    );
  }
}

class AppSessionScope extends InheritedWidget {
  const AppSessionScope({
    super.key,
    required this.session,
    required super.child,
  });

  final AppSession session;

  static AppSession? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppSessionScope>()
        ?.session;
  }

  static AppSession of(BuildContext context) {
    final session = maybeOf(context);
    assert(() {
      if (session == null) {
        final currentUser = FirebaseAuth.instance.currentUser;
        debugPrint(
          currentUser == null
              ? 'AppSessionScope missing for ${context.widget.runtimeType}; using unauthenticated fallback session.'
              : 'AppSessionScope missing for ${context.widget.runtimeType}; using Firebase-auth fallback session for uid=${currentUser.uid} isAnonymous=${currentUser.isAnonymous}.',
        );
      }
      return true;
    }());
    return session ?? AppSession.fallbackFromAuth();
  }

  @override
  bool updateShouldNotify(AppSessionScope oldWidget) {
    return oldWidget.session.userId != session.userId ||
        oldWidget.session.access.tier != session.access.tier ||
        oldWidget.session.userData != session.userData;
  }
}
