// lib/features/auth/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'sign_in_page.dart';

/// Zeigt SignIn solange kein User eingeloggt ist.
/// Wenn eingeloggt, zeigt es [signedIn].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.signedIn});

  final Widget signedIn;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Material(child: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) {
          return const SignInPage();
        }
        return signedIn;
      },
    );
  }
}
