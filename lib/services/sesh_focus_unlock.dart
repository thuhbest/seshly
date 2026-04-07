import 'sesh_focus_service.dart';
import 'secure_entitlements_service.dart';

class SeshFocusUnlock {
  static Future<bool> unlockEarly() async {
    try {
      await SecureEntitlementsService().unlockSeshFocusEarly();
      await SeshFocusService.stop();
      return true;
    } catch (_) {
      return false;
    }
  }
}
