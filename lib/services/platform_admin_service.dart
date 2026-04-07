import 'package:firebase_auth/firebase_auth.dart';

class PlatformAdminService {
  const PlatformAdminService();

  Future<bool> isCurrentUserPlatformAdmin({
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    final token = await user.getIdTokenResult(forceRefresh);
    final claims = token.claims ?? const <String, dynamic>{};
    return claims['admin'] == true ||
        (claims['role']?.toString().trim().toLowerCase() ?? '') == 'admin' ||
        (claims['platformRole']?.toString().trim().toLowerCase() ?? '') ==
            'admin';
  }
}
