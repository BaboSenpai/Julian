// lib/dev_force_signout.dart
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

/// Aktivierbar per: --dart-define=LOGOUT=1
Future<void> devForceSignOutIfRequested() async {
  const String kLogout = String.fromEnvironment('LOGOUT', defaultValue: '0');
  if (kLogout == '1') {
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
      // ignore: avoid_print
      print('[dev] Forced signOut done (LOGOUT=1)');
    } catch (e) {
      // ignore: avoid_print
      print('[dev] signOut failed: ');
    }
  }
}