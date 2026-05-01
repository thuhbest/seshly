import 'package:flutter/material.dart';

import 'app_access.dart';
import 'app_session_scope.dart';

class AccessController {
  static AppSession session(BuildContext context) =>
      AppSessionScope.of(context);

  static AppCapabilitySet access(BuildContext context) =>
      session(context).access;

  static bool can(BuildContext context, AppCapability capability) {
    return access(context).can(capability);
  }

  static bool isInstantTutorModeFor(BuildContext context) =>
      session(context).identity.isInstantTutor;

  static Future<bool> guard(
    BuildContext context, {
    required AppCapability capability,
  }) async {
    if (can(context, capability)) return true;
    await showAccessRestrictionSheet(context, capability: capability);
    return false;
  }
}

typedef AppCapabilitySet = AppAccessProfile;
